//
//  TransactionDraft.swift
//  轻点记账
//
//  识别结果 → 待确认草稿。UI 在草稿上改金额 / 分类 / 备注，
//  确认后由 RecordService 落库。
//

import Foundation
import UIKit

struct TransactionDraft: Identifiable, Equatable {
    var id: UUID = UUID()

    var kind: TransactionKind = .expense
    var amountCents: Int = 0
    var merchant: String = ""
    var item: String = ""
    var note: String = ""
    var categoryName: String = "其他"
    var categoryID: UUID?

    var occurredAt: Date = .now
    var platform: PaymentPlatform = .other
    var account: String = ""
    var orderNumber: String = ""

    var source: TransactionSource = .backTap
    var confidence: Double = 0
    /// 收支方向是否足够确定（false 时先让用户选收入/支出）
    var kindIsCertain: Bool = true

    var imageHash: String = ""
    var perceptualHash: String = ""
    var rawText: String = ""

    /// 原始截图（仅内存持有，不落盘、不上传）
    var imageData: Data?

    /// 分类推荐说明，例如「商户命中「中石化」」
    var classificationReason: String = ""
    /// 解析过程备注
    var parserNotes: [String] = []

    var thumbnail: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }

    var amountText: String { MoneyFormatter.string(cents: amountCents) }

    var isAmountValid: Bool { amountCents > 0 }

    /// 从 OCR 结果构造草稿
    static func from(
        parsed: ParsedReceipt,
        classification: ClassificationResult,
        source: TransactionSource,
        imageData: Data?,
        imageHash: String,
        perceptualHash: String,
        categories: [Category]
    ) -> TransactionDraft {
        var draft = TransactionDraft()
        draft.kind = parsed.kind
        draft.kindIsCertain = parsed.kindConfidence >= 0.7
        draft.amountCents = parsed.amountCents ?? 0
        draft.merchant = parsed.merchant
        draft.item = parsed.item
        draft.occurredAt = parsed.occurredAt
        draft.platform = parsed.platform
        draft.account = parsed.account
        draft.orderNumber = parsed.orderNumber
        draft.source = source
        draft.confidence = parsed.confidence
        draft.imageHash = imageHash
        draft.perceptualHash = perceptualHash
        draft.rawText = parsed.rawText
        draft.imageData = imageData
        draft.classificationReason = classification.reason
        draft.parserNotes = parsed.notes
        draft.categoryName = classification.categoryName
        draft.categoryID = SeedData.category(named: classification.categoryName, in: categories)?.id
        return draft
    }
}

// MARK: - 分类结果

struct ClassificationResult: Equatable {
    let categoryName: String
    /// 0...1
    let confidence: Double
    /// 给用户看的推荐理由
    let reason: String

    static let fallbackExpense = ClassificationResult(categoryName: "其他", confidence: 0.2, reason: "没有匹配到可用规则")
    static let fallbackIncome = ClassificationResult(categoryName: "工资收入", confidence: 0.2, reason: "默认为收入类目")
}
