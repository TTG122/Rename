//
//  RootView.swift
//  轻点记账
//
//  根视图：承载 4 个 Tab、全局轻提示、识别确认面板、引导页和 Face ID 锁。
//  「双击背面 → 确认面板」就是靠这里的 sheet 实现的：App 被唤起后只显示一个
//  半屏面板，不展示完整界面，用户确认完 2 秒自动消失。
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query private var categories: [Category]

    @State private var isLocked = false
    @State private var didBootstrap = false

    var body: some View {
        @Bindable var router = router

        ZStack(alignment: .top) {
            TabView(selection: $router.selectedTab) {
                HomeView()
                    .tag(AppTab.home)
                    .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.symbol) }

                LedgerView()
                    .tag(AppTab.ledger)
                    .tabItem { Label(AppTab.ledger.title, systemImage: AppTab.ledger.symbol) }

                StatsView()
                    .tag(AppTab.stats)
                    .tabItem { Label(AppTab.stats.title, systemImage: AppTab.stats.symbol) }

                SettingsView()
                    .tag(AppTab.settings)
                    .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbol) }
            }
            .tint(Theme.brand)

            // 轻提示（已记账 + 撤销）
            if let toast = router.toast {
                ToastView(
                    toast: toast,
                    onUndo: {
                        toast.undo?()
                        router.dismissToast()
                    },
                    onDismiss: { router.dismissToast() }
                )
                .padding(.top, 8)
                .zIndex(10)
            }

            if isLocked {
                LockScreenView {
                    unlock()
                }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: router.toast?.id)
        .sheet(item: $router.pendingDraft) { draft in
            CaptureConfirmView(draft: draft)
                .environment(router)
                .environment(settings)
        }
        .fullScreenCover(isPresented: $router.showOnboarding) {
            OnboardingView()
                .environment(settings)
                .environment(router)
        }
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            SeedData.prepare(context: modelContext)
            SnapshotWriter.refresh(in: modelContext)
            router.showOnboarding = !settings.hasCompletedOnboarding
            if settings.faceIDEnabled {
                isLocked = true
                unlock()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                if settings.faceIDEnabled { isLocked = true }
            } else if newPhase == .active {
                // 处理分享扩展投递进来的图片
                Task { await InboxIngestor.drain(context: modelContext, categories: categories) }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "qingdianjizhang" else { return }
            Task { await InboxIngestor.drain(context: modelContext, categories: categories) }
        }
    }

    private func unlock() {
        guard settings.faceIDEnabled, BiometricLock.isAvailable else {
            isLocked = false
            return
        }
        Task {
            let success = await BiometricLock.unlock()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    isLocked = !success
                }
            }
        }
    }
}

// MARK: - 锁屏

private struct LockScreenView: View {
    var onUnlock: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.brand)
                Text("轻点记账已锁定")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Button("用 \(BiometricLock.biometryName) 解锁", action: onUnlock)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 60)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - 收件箱处理

@MainActor
enum InboxIngestor {
    static func drain(context: ModelContext, categories: [Category]) async {
        let items = SharedInbox.pendingItems()
        guard !items.isEmpty else { return }

        for item in items {
            if let data = SharedInbox.imageData(for: item) {
                let outcome = await CapturePipeline.process(
                    imageData: data,
                    source: TransactionSource(rawValue: item.source) ?? .share,
                    context: context,
                    categories: categories
                )
                CapturePipeline.ingestAndRoute(outcome: outcome, context: context)
            } else if let text = item.text, !text.isEmpty {
                let outcome = await CapturePipeline.process(
                    text: text,
                    source: TransactionSource(rawValue: item.source) ?? .share,
                    context: context,
                    categories: categories
                )
                CapturePipeline.ingestAndRoute(outcome: outcome, context: context)
            }
            SharedInbox.remove(item)
        }
        AppRouter.shared.pendingInboxCount = SharedInbox.pendingCount()
    }
}
