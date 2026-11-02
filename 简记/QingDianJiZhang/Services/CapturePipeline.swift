//
//  CapturePipeline.swift
//  轻点记账
//
//  识别流水线（唯一入口）：
//  图片 → Vision OCR → 文本解析 → 分类推荐 → 查重 → 草稿 / 自动入账
//
//  App Intent、分享扩展、相册导入、小票拍摄、批量导入全部复用这里。
//

import Foundation
import SwiftData
import UIKit

@MainActor
enum CapturePipeline {

    enum Outcome {
        /// 需要用户确认
        case needsConfirmation(TransactionDraft)
        /// 智能自动模式下已直接入账
        case saved(Transaction)
        /// 失败
        case failed(String)
    }

    // MARK: - 图片入口

    static func process(
        imageData: Data,
        source: TransactionSource,
        context: ModelContext,
        categories: [Category],
        settings: SettingsStore = .shared
    ) async -> Outcome {
        guard let image = UIImage(data: imageData) else {
            return .failed("图片无法读取")
        }

        let document: OCRDocument
        do {
            document = try await OCRService.shared.recognize(image: image)
        } catch {
            return .failed(error.localizedDescription)
        }

        let parsed = ReceiptParser.parse(document: document)
        return await finalize(
            parsed: parsed,
            source: source,
            imageData: imageData,
            imageHash: document.imageHash,
            perceptualHash: document.perceptualHash,
            context: context,
            categories: categories,
            settings: settings
        )
    }

    // MARK: - 文本入口（语音 / 手动粘贴 / 其他 App 分享文字）

    static func process(
        text: String,
        source: TransactionSource,
        context: ModelContext,
        categories: [Category],
        settings: SettingsStore = .shared
    ) async -> Outcome {
        let parsed: ParsedReceipt
        if source == .voice {
            parsed = VoiceCommandParser.parse(text: text)
        } else {
            parsed = ReceiptParser.parse(text: text)
        }
        return await finalize(
            parsed: parsed,
            source: source,
            imageData: nil,
            imageHash: ImageHash.sha256(of: Data(text.utf8)),
            perceptualHash: "",
            context: context,
            categories: categories,
            settings: settings
        )
    }

    // MARK: - 公共收尾

    private static func finalize(
        parsed: ParsedReceipt,
        source: TransactionSource,
        imageData: Data?,
        imageHash: String,
        perceptualHash: String,
        context: ModelContext,
        categories: [Category],
        settings: SettingsStore
    ) async -> Outcome {
        let rules = learnedRules(in: context)
        let classifier = HybridClassifier()
        let classification = classifier.classify(
            ClassificationInput(
                merchant: parsed.merchant,
                item: parsed.item,
                rawText: parsed.rawText,
                kind: parsed.kind,
                learnedRules: rules,
                availableCategories: availableNames(categories, kind: parsed.kind)
            )
        )

        let draft = TransactionDraft.from(
            parsed: parsed,
            classification: classification,
            source: source,
            imageData: imageData,
            imageHash: imageHash,
            perceptualHash: perceptualHash,
            categories: categories
        )

        // 金额都没识别到 → 一定要用户确认（并引导手动填）
        guard draft.amountCents > 0 else {
            return .needsConfirmation(draft)
        }

        // 智能自动模式判定
        let isAuto = settings.recordMode == .smartAuto
            && draft.kindIsCertain
            && draft.confidence >= settings.autoThreshold

        guard isAuto else {
            return .needsConfirmation(draft)
        }

        // 自动入账前必须过查重
        if case .suspected = checkDuplicate(draft, in: context) {
            return .needsConfirmation(draft)
        }

        let transaction = RecordService.save(draft: draft, in: context, categories: categories)
        return .saved(transaction)
    }

    /// 给 App Intent / 分享扩展用的「一步到位」封装：直接交给 AppRouter
    @discardableResult
    static func ingestAndRoute(
        outcome: Outcome,
        context: ModelContext
    ) -> Bool {
        switch outcome {
        case .needsConfirmation(let draft):
            AppRouter.shared.presentConfirm(draft)
            return true
        case .saved(let transaction):
            let id = transaction.id
            AppRouter.shared.showSaved(transaction: transaction) {
                deleteByID(id, context: context)
            }
            return true
        case .failed(let message):
            AppRouter.shared.showToast(
                AppToast(title: "识别失败", subtitle: message, symbol: "exclamationmark.triangle.fill", tint: .orange),
                autoDismissAfter: 3
            )
            return false
        }
    }

    static func deleteByID(_ id: UUID, context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        if let target = all.first(where: { $0.id == id }) {
            RecordService.undo(target, in: context)
        }
    }

    // MARK: - 上下文辅助

    static func learnedRules(in context: ModelContext) -> [String: String] {
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let merchantRules = (try? context.fetch(FetchDescriptor<MerchantRule>())) ?? []
        var merged = MerchantLearning.rules(from: transactions)
        // 显式规则优先
        for (key, value) in MerchantLearning.rules(from: merchantRules) {
            merged[key] = value
        }
        return merged
    }

    static func availableNames(_ categories: [Category], kind: TransactionKind) -> [String] {
        let names = categories
            .filter { !$0.isArchived && $0.isAvailable(for: kind) }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
        return names.isEmpty ? SystemCategories.all.map(\.name) : names
    }

    static func checkDuplicate(_ draft: TransactionDraft, in context: ModelContext) -> DuplicateVerdict {
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        return DuplicateDetector.check(draft: draft, against: all)
    }
}
