//
//  RecordIntents.swift
//  轻点记账
//
//  App Intents：快捷指令「轻点记账」的落点。
//  双击背面 → 运行快捷指令 → 把截图传进来 → 识别 → 打开确认面板。
//
//  说明：iOS 不允许 App Intent 在其他 App 之上直接弹出自定义 UI，
//  所以我们用 openAppWhenRun = true 唤起本 App，App 只显示一个半屏确认面板，
//  确认完立刻收起，视觉上等同于系统弹层。
//

import AppIntents
import Foundation
import SwiftData
import UIKit

// MARK: - 识别截图并记账

struct RecordFromImageIntent: AppIntent {
    static var title: LocalizedStringResource = "识别并记账"
    static var description: IntentDescription = IntentDescription("把支付截图交给轻点记账，自动识别金额、商户和分类。")

    /// 需要 App 在前台才能显示确认面板
    static var openAppWhenRun: Bool = true

    @Parameter(title: "截图", description: "支付成功页的截图")
    var image: IntentFile?

    @Parameter(title: "文字", description: "也可以直接传一段支付文字")
    var text: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = ModelContainerProvider.shared
        let context = container.mainContext
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []

        // 1. 优先处理图片
        if let image, !image.data.isEmpty {
            let outcome = await CapturePipeline.process(
                imageData: image.data,
                source: .backTap,
                context: context,
                categories: categories
            )
            CapturePipeline.ingestAndRoute(outcome: outcome, context: context)
            return .result(dialog: dialogText(for: outcome))
        }

        // 2. 其次是文字
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let outcome = await CapturePipeline.process(
                text: text,
                source: .backTap,
                context: context,
                categories: categories
            )
            CapturePipeline.ingestAndRoute(outcome: outcome, context: context)
            return .result(dialog: dialogText(for: outcome))
        }

        // 3. 什么都没有：打开手动记账
        AppRouter.shared.showToast(
            AppToast(title: "没收到截图", subtitle: "在快捷指令里加一步「获取图像」", symbol: "photo.badge.exclamationmark", tint: .orange),
            autoDismissAfter: 3
        )
        return .result(dialog: "没有收到截图，已为你打开轻点记账。")
    }

    @MainActor
    private func dialogText(for outcome: CapturePipeline.Outcome) -> String {
        switch outcome {
        case .saved(let transaction):
            return "已记账 ¥\(MoneyFormatter.string(cents: transaction.amountCents))，分类：\(transaction.categoryName)"
        case .needsConfirmation(let draft):
            if draft.amountCents > 0 {
                return "识别到 ¥\(draft.amountText)，请确认分类"
            }
            return "没识别到金额，请在面板里手动填写"
        case .failed(let message):
            return "识别失败：\(message)"
        }
    }
}

// MARK: - 纯文字快速记账

struct QuickTextRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "说一句就记账"
    static var description: IntentDescription = IntentDescription("用一句话记账，例如「今天中午吃饭花了28元」。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "内容", description: "例如：中午吃饭28元")
    var content: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = ModelContainerProvider.shared
        let context = container.mainContext
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []

        let outcome = await CapturePipeline.process(
            text: content,
            source: .backTap,
            context: context,
            categories: categories
        )
        CapturePipeline.ingestAndRoute(outcome: outcome, context: context)

        switch outcome {
        case .saved(let transaction):
            return .result(dialog: "已记账 ¥\(MoneyFormatter.string(cents: transaction.amountCents))")
        case .needsConfirmation(let draft):
            return .result(dialog: "识别到 ¥\(draft.amountText)，请确认分类")
        case .failed(let message):
            return .result(dialog: "识别失败：\(message)")
        }
    }
}

// MARK: - 打开 App 准备记账

struct OpenQuickRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "打开轻点记账"
    static var description: IntentDescription = IntentDescription("打开 App 并停在记账入口。")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.selectedTab = .home
        return .result()
    }
}
