//
//  AppRouter.swift
//  轻点记账
//
//  全局导航 / 弹层 / Toast 状态。App Intents、Share Extension 的启动参数
//  最终都汇总到这里，由根视图统一呈现（保证「不进入完整 App 也能记账」）。
//

import SwiftUI
import Observation

enum AppTab: String, Hashable, CaseIterable {
    case home
    case ledger
    case stats
    case settings

    var title: String {
        switch self {
        case .home: return "首页"
        case .ledger: return "账单"
        case .stats: return "统计"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .ledger: return "list.bullet.rectangle"
        case .stats: return "chart.pie.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct AppToast: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var subtitle: String = ""
    var symbol: String = "checkmark.circle.fill"
    var tint: Color = Theme.brand
    var undo: (() -> Void)?

    static func == (lhs: AppToast, rhs: AppToast) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// 非 nil 时弹出「识别确认面板」
    var pendingDraft: TransactionDraft?
    /// 轻量提示条
    var toast: AppToast?
    var selectedTab: AppTab = .home
    /// 从分享扩展 / 文件导入带进来的待处理文件
    var pendingInboxCount: Int = 0
    /// 首次引导
    var showOnboarding: Bool = false

    private var toastTask: Task<Void, Never>?

    private init() {}

    // MARK: - 确认面板

    func presentConfirm(_ draft: TransactionDraft) {
        pendingDraft = draft
        Haptics.impact(.light)
    }

    func dismissConfirm() {
        pendingDraft = nil
    }

    // MARK: - Toast

    func showToast(_ toast: AppToast, autoDismissAfter seconds: TimeInterval = 2.0) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            self.toast = toast
        }
        Haptics.success()

        guard seconds > 0 else { return }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    self?.toast = nil
                }
            }
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            toast = nil
        }
    }

    // MARK: - 记账成功的标准提示

    func showSaved(transaction: Transaction, undoHandler: @escaping () -> Void) {
        showToast(
            AppToast(
                title: "已记账 ¥\(MoneyFormatter.string(cents: transaction.amountCents))",
                subtitle: "分类：\(transaction.categoryName)",
                symbol: "checkmark.circle.fill",
                tint: Theme.brand,
                undo: undoHandler
            ),
            autoDismissAfter: 2.0
        )
    }
}
