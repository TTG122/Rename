//
//  SettingsView.swift
//  轻点记账
//

import SwiftUI
import SwiftData
import UserNotifications
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppRouter.self) private var router

    @Query private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query private var rules: [MerchantRule]
    @Query private var budgets: [Budget]

    @State private var showCategoryManager = false
    @State private var showBudgetEditor = false
    @State private var showImport = false
    @State private var showSetupGuide = false
    @State private var showPrivacy = false
    @State private var showDeleteAlert = false
    @State private var sharePayload: SharePayload?

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            List {
                // 记账模式
                Section {
                    Picker("记账模式", selection: $settings.recordMode) {
                        ForEach(RecordMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                    Text(settings.recordMode.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)

                    if settings.recordMode == .smartAuto {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("自动记账置信度")
                                    .font(.system(size: 14))
                                Spacer()
                                Text(settings.thresholdPercentText)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.brand)
                            }
                            Slider(value: $settings.autoThreshold, in: 0.5...0.99, step: 0.01)
                                .tint(Theme.brand)
                            Text("识别置信度达到这个值就直接入账，低于它会先问你。调高更安全，调低更省事。")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                } header: {
                    Text("记账方式")
                }

                // 双击背面
                Section {
                    Button {
                        showSetupGuide = true
                    } label: {
                        SettingsRow(symbol: "hand.tap.fill", title: "双击背面设置教程", subtitle: "设置一次，以后 2 秒记一笔") {
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        openShortcutsApp()
                    } label: {
                        SettingsRow(symbol: "square.stack.3d.up.fill", title: "打开快捷指令 App", subtitle: "重新安装或编辑「轻点记账」快捷指令") {
                            Image(systemName: "arrow.up.forward.app").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsRow(symbol: "tray.full.fill", title: "分享收件箱", subtitle: nil, tint: .blue) {
                        Text("\(SharedInbox.pendingCount()) 条待处理")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                } header: {
                    Text("双击背面记账")
                }

                // 账本
                Section {
                    Button {
                        showCategoryManager = true
                    } label: {
                        SettingsRow(symbol: "square.grid.2x2.fill", title: "分类管理", subtitle: "\(categories.count) 个分类 · \(rules.count) 条规则", tint: .orange) {
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showBudgetEditor = true
                    } label: {
                        SettingsRow(symbol: "target", title: "预算管理", subtitle: currentBudgetText, tint: .purple) {
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsRow(symbol: "creditcard.fill", title: "默认账户", tint: .teal) {
                        TextField("默认账户", text: $settings.defaultAccount)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text("账本")
                }

                // 数据
                Section {
                    Button {
                        showImport = true
                    } label: {
                        SettingsRow(symbol: "tray.and.arrow.down.fill", title: "导入账单", subtitle: "微信 / 支付宝 / 银行 CSV、Excel", tint: .blue) {
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        exportAll()
                    } label: {
                        SettingsRow(symbol: "square.and.arrow.up.fill", title: "导出全部数据", subtitle: "CSV / Excel，可随时带走", tint: .indigo) {
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("数据")
                }

                // 安全与同步
                Section {
                    Toggle(isOn: $settings.faceIDEnabled) {
                        SettingsRow(symbol: "faceid", title: BiometricLock.biometryName, subtitle: "打开 App 时需要验证", tint: .green) { EmptyView() }
                    }

                    Toggle(isOn: $settings.iCloudSyncEnabled) {
                        SettingsRow(symbol: "icloud.fill", title: "iCloud 同步", subtitle: "在多台 iPhone 间同步账单（需登录 iCloud）", tint: .cyan) { EmptyView() }
                    }

                    Toggle(isOn: $settings.cloudAIEnabled) {
                        SettingsRow(symbol: "cloud.fill", title: "云端 AI 分析（默认关闭）", subtitle: "开启后才会把脱敏后的统计结果发到云端", tint: .gray) { EmptyView() }
                    }
                } header: {
                    Text("安全与同步")
                } footer: {
                    Text("OCR 识别和分类全部在本机完成。关闭云端 AI 时，App 不会向任何服务器发送账单数据。")
                }

                // 通知
                Section {
                    Toggle(isOn: $settings.monthlyReminderEnabled) {
                        SettingsRow(symbol: "bell.fill", title: "每月账单提醒", subtitle: "月初提醒你看一眼上月月报", tint: .red) { EmptyView() }
                    }
                    .onChange(of: settings.monthlyReminderEnabled) { _, enabled in
                        if enabled { requestNotificationPermission() }
                    }
                } header: {
                    Text("提醒")
                }

                // 隐私
                Section {
                    Button {
                        showPrivacy = true
                    } label: {
                        SettingsRow(symbol: "hand.raised.fill", title: "隐私说明", tint: .gray) {
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        SettingsRow(symbol: "trash.fill", title: "删除全部数据", subtitle: "永久删除本机所有账单和规则", tint: .red) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("隐私与数据")
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Self.versionText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    HStack {
                        Text("账单总数")
                        Spacer()
                        Text("\(transactions.filter { !$0.isDeleted }.count) 笔")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    HStack {
                        Text("分类")
                        Spacer()
                        Text("\(categories.count) 个")
                            .foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text("关于")
                } footer: {
                    Text("轻点记账 · 双击背面 2 秒记一笔。所有账单只存在你的 iPhone 上。")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showCategoryManager) {
                CategoryManagerView()
            }
            .sheet(isPresented: $showBudgetEditor) {
                BudgetEditorView()
            }
            .sheet(isPresented: $showImport) {
                ImportView()
                    .environment(router)
            }
            .sheet(isPresented: $showSetupGuide) {
                SetupGuideView()
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyPolicyView()
            }
            .sheet(item: $sharePayload) { payload in
                ActivityView(items: payload.items)
            }
            .alert("删除全部数据？", isPresented: $showDeleteAlert) {
                Button("永久删除", role: .destructive) { deleteAllData() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有账单、分类规则、预算都会被删除，无法恢复。建议先导出一份 CSV。")
            }
        }
    }

    // MARK: - 辅助

    private var currentBudgetText: String {
        let budget = budgets.first { $0.isTotalBudget && ($0.monthKey.isEmpty || $0.monthKey == MonthKey.string(for: .now)) }
        guard let budget else { return "还没设置" }
        return "总预算 ¥\(MoneyFormatter.grouped(cents: budget.amountCents))"
    }

    private static var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func openShortcutsApp() {
        if let url = URL(string: "shortcuts://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func exportAll() {
        do {
            let url = try ExportService.exportCSVFile(transactions: transactions.filter { !$0.isDeleted })
            sharePayload = SharePayload(items: [url])
        } catch {
            router.showToast(
                AppToast(title: "导出失败", subtitle: error.localizedDescription, symbol: "exclamationmark.triangle", tint: .orange),
                autoDismissAfter: 2.5
            )
        }
    }

    private func deleteAllData() {
        for item in transactions { modelContext.delete(item) }
        for rule in rules { modelContext.delete(rule) }
        for budget in budgets { modelContext.delete(budget) }
        for category in categories { modelContext.delete(category) }
        try? modelContext.save()
        SeedData.prepare(context: modelContext)
        SnapshotWriter.refresh(in: modelContext)
        SharedInbox.clear()
        Haptics.warning()
        router.showToast(AppToast(title: "已清空", subtitle: "所有账单和规则都已删除", symbol: "checkmark.circle.fill"), autoDismissAfter: 2)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}
