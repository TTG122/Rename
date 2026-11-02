//
//  Transaction.swift
//  简记
//
//  核心账单模型。
//
//  设计说明：
//  1. 金额统一以「分」为单位的 Int 落库（amountCents），彻底规避浮点误差。
//  2. 分类采用 categoryID + categoryName 冗余字段，而不使用 SwiftData 关系。
//     原因：关系模型在 SwiftData 的批量删除 / 迁移 / Widget 共享读取中容易
//     产生悬空引用；个人记账 App 的分类数量很小，冗余字符串成本极低。
//  3. 所有属性都带默认值、不使用 @Attribute(.unique)：
//     这是 SwiftData 开启 CloudKit 同步的硬性要求（CloudKit 不支持唯一约束）。
//     唯一性由 App 层的 dedupeKey + RecordService 保证。
//

import Foundation
import SwiftData

@Model
final class Transaction {
    // MARK: 主键

    var id: UUID = UUID()

    // MARK: 收支
    var kindRaw: String = "expense"
    /// 金额，单位：分。永远为正数，方向由 kindRaw 决定。
    var amountCents: Int = 0

    // MARK: 内容
    /// 商户名称，例如「星巴克(国贸店)」
    var merchant: String = ""
    /// 商品 / 订单内容
    var item: String = ""
    /// 备注
    var note: String = ""

    // MARK: 分类
    var categoryID: UUID?
    var categoryName: String = "其他"

    // MARK: 时间
    /// 实际发生时间（支付时间）
    var occurredAt: Date = Date.now
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // MARK: 支付信息
    var platformRaw: String = "other"
    /// 支付账户，例如「招商银行储蓄卡(1234)」。绝不存完整卡号。
    var account: String = ""
    var orderNumber: String = ""

    // MARK: 来源与识别
    var sourceRaw: String = "manual"
    /// 识别置信度 0...1
    var confidence: Double = 1.0
    /// 原始图片 SHA256
    var imageHash: String = ""
    /// 查重指纹
    var dedupeKey: String = ""

    /// 软删除标记，用于「撤销」和回收站
    var isDeleted: Bool = false

    init(
        id: UUID = UUID(),
        kind: TransactionKind,
        amountCents: Int,
        merchant: String = "",
        item: String = "",
        note: String = "",
        categoryID: UUID? = nil,
        categoryName: String = "其他",
        occurredAt: Date = .now,
        platform: PaymentPlatform = .other,
        account: String = "",
        orderNumber: String = "",
        source: TransactionSource = .manual,
        confidence: Double = 1.0,
        imageHash: String = ""
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.amountCents = max(0, amountCents)
        self.merchant = merchant
        self.item = item
        self.note = note
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.occurredAt = occurredAt
        self.platformRaw = platform.rawValue
        self.account = account
        self.orderNumber = orderNumber
        self.sourceRaw = source.rawValue
        self.confidence = confidence
        self.imageHash = imageHash
        self.dedupeKey = ""
        self.isDeleted = false
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
    }
}

// MARK: - 计算属性

extension Transaction {
    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var platform: PaymentPlatform {
        get { PaymentPlatform(rawValue: platformRaw) ?? .other }
        set { platformRaw = newValue.rawValue }
    }

    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// 以元为单位的金额（用于展示与计算）
    var amount: Double {
        Double(amountCents) / 100.0
    }

    /// 带符号的展示金额，例如 "-36.00"
    var signedAmountText: String {
        let base = MoneyFormatter.string(cents: amountCents)
        return kind.sign + base
    }

    /// 列表主标题：优先商户，其次商品，最后分类
    var displayTitle: String {
        if !merchant.isEmpty { return merchant }
        if !item.isEmpty { return item }
        return categoryName
    }

    /// 副标题
    var displaySubtitle: String {
        var parts: [String] = []
        if !item.isEmpty, item != merchant { parts.append(item) }
        if !note.isEmpty { parts.append(note) }
        if parts.isEmpty { parts.append(platform.title) }
        return parts.joined(separator: " · ")
    }

    /// 刷新查重指纹
    func refreshDedupeKey() {
        dedupeKey = DedupeKey.make(
            kind: kind,
            amountCents: amountCents,
            merchant: merchant,
            orderNumber: orderNumber,
            occurredAt: occurredAt,
            imageHash: imageHash
        )
        updatedAt = .now
    }
}

// MARK: - 查重指纹

enum DedupeKey {
    /// 强指纹：订单号存在时，订单号即唯一
    static func make(
        kind: TransactionKind,
        amountCents: Int,
        merchant: String,
        orderNumber: String,
        occurredAt: Date,
        imageHash: String
    ) -> String {
        let normalizedMerchant = TextNormalizer.normalize(merchant)
        if !orderNumber.isEmpty {
            return "ord|\(orderNumber)"
        }
        if !imageHash.isEmpty {
            return "img|\(imageHash)"
        }
        // 时间取到 3 分钟粒度，避免秒级抖动
        let minute = Int(occurredAt.timeIntervalSince1970 / 60)
        return "amt|\(kind.rawValue)|\(amountCents)|\(normalizedMerchant)|\(minute / 3)"
    }
}

// MARK: - 文本归一化

enum TextNormalizer {
    /// 归一化：去空白、去标点、转小写
    static func normalize(_ text: String) -> String {
        var s = text.lowercased()
        let removeSet = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        s = s.components(separatedBy: removeSet).joined()
        let map: [Character: Character] = [
            "（": "(", "）": ")", "：": ":", "，": ",",
            "￥": "¥", "－": "-", "—": "-"
        ]
        s = String(s.map { map[$0] ?? $0 })
        return s
    }

    /// 是否包含任意关键词
    static func contains(_ text: String, anyOf keywords: [String]) -> Bool {
        let n = normalize(text)
        return keywords.contains { n.contains(normalize($0)) }
    }
}
