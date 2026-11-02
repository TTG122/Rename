//
//  MerchantRule.swift
//  轻点记账
//
//  商户 → 分类的学习规则。用户手动改过一次分类后，本表记下这条映射，
//  下次遇到同一商户直接命中，置信度 0.97。
//

import Foundation
import SwiftData

@Model
final class MerchantRule {
    var id: UUID = UUID()
    /// 归一化后的商户关键词（用于匹配）
    var pattern: String = ""
    /// 展示用的原始商户名
    var displayName: String = ""
    var categoryID: UUID?
    var categoryName: String = "其他"
    var hitCount: Int = 1
    var createdAt: Date = Date.now
    var lastUsedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        pattern: String,
        displayName: String,
        categoryID: UUID?,
        categoryName: String
    ) {
        self.id = id
        self.pattern = pattern
        self.displayName = displayName
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.hitCount = 1
        self.createdAt = .now
        self.lastUsedAt = .now
    }
}

// MARK: - 预算

@Model
final class Budget {
    var id: UUID = UUID()
    /// "2026-11"；空字符串表示「长期默认预算」
    var monthKey: String = ""
    var amountCents: Int = 0
    /// nil 表示总预算
    var categoryID: UUID?
    var categoryName: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        monthKey: String,
        amountCents: Int,
        categoryID: UUID? = nil,
        categoryName: String = ""
    ) {
        self.id = id
        self.monthKey = monthKey
        self.amountCents = amountCents
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.createdAt = .now
        self.updatedAt = .now
    }
}

extension Budget {
    var isTotalBudget: Bool { categoryID == nil }
}

// MARK: - 月份工具

enum MonthKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    static func string(for date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }

    static func displayTitle(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }

    static func monthRange(of date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: comps) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? date
        return (start, end)
    }

    static func previousMonth(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: -1, to: date) ?? date
    }
}
