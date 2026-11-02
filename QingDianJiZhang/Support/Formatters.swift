//
//  Formatters.swift
//  轻点记账
//

import Foundation

enum MoneyFormatter {
    /// 分 → "36.00"
    static func string(cents: Int) -> String {
        let yuan = Double(cents) / 100.0
        return String(format: "%.2f", yuan)
    }

    /// 分 → "¥36.00"
    static func currency(cents: Int, symbol: String = "¥") -> String {
        symbol + string(cents: cents)
    }

    /// 分 → "1,234.00"
    static func grouped(cents: Int) -> String {
        let yuan = Double(cents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: yuan)) ?? String(format: "%.2f", yuan)
    }

    /// 元字符串 / OCR 文本 → 分
    static func cents(fromYuanText text: String) -> Int? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value.isFinite, value >= 0, value < 100_000_000 else {
            return nil
        }
        return Int((value * 100).rounded())
    }

    /// 大额简写："1.2万"
    static func compact(cents: Int) -> String {
        let yuan = Double(cents) / 100.0
        if yuan >= 10_000 {
            return String(format: "%.1f万", yuan / 10_000)
        }
        return String(format: "%.0f", yuan)
    }
}

enum DateText {
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()

    static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f
    }()

    /// 「今天」「昨天」「昨天 · 周三」「11月2日」
    static func dayTitle(for date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        if calendar.isDateInTomorrow(date) { return "明天" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return weekdayFormatter.string(from: date)
        }
        let comps = calendar.dateComponents([.year], from: date)
        let currentYear = calendar.component(.year, from: .now)
        if comps.year == currentYear {
            return dayFormatter.string(from: date)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }

    static func sectionTitle(for date: Date) -> String {
        dayTitle(for: date) + " · " + timeFormatter.string(from: date)
    }
}
