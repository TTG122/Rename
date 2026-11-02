//
//  SnapshotWriter.swift
//  轻点记账
//
//  给 WidgetKit 用的轻量快照。Widget 进程不直接打开 SwiftData 主库，
//  只读这个 JSON —— 快、稳、不会因为 schema 变化导致小组件崩溃。
//

import Foundation
import SwiftData
import WidgetKit

enum SnapshotWriter {
    struct CategorySlice: Codable, Identifiable {
        var id: String { name }
        var name: String
        var colorHex: String
        var amountCents: Int
    }

    struct Snapshot: Codable {
        var updatedAt: Date
        var todayExpenseCents: Int
        var todayIncomeCents: Int
        var monthExpenseCents: Int
        var monthIncomeCents: Int
        var monthBudgetCents: Int
        var monthKey: String
        var topCategories: [CategorySlice]
        var lastTransactionTitle: String
        var lastTransactionAmountCents: Int
        var lastTransactionTime: Date

        static let placeholder = Snapshot(
            updatedAt: .now,
            todayExpenseCents: 8600,
            todayIncomeCents: 0,
            monthExpenseCents: 568_000,
            monthIncomeCents: 1_200_000,
            monthBudgetCents: 800_000,
            monthKey: MonthKey.string(for: .now),
            topCategories: [
                CategorySlice(name: "吃饭", colorHex: "#FF9F0A", amountCents: 156_000),
                CategorySlice(name: "购物", colorHex: "#FF6B6B", amountCents: 98_000),
                CategorySlice(name: "交通", colorHex: "#4C9AFF", amountCents: 46_000)
            ],
            lastTransactionTitle: "星巴克",
            lastTransactionAmountCents: 3600,
            lastTransactionTime: .now
        )
    }

    private static let fileName = "widget-snapshot.json"

    static var fileURL: URL? {
        AppGroup.workingURL?.appendingPathComponent(fileName)
    }

    /// 从数据重新计算并写入
    @MainActor
    static func refresh(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let active = all.filter { !$0.isDeleted }
        let now = Date.now
        let calendar = Calendar.current
        let monthStart = MonthKey.monthRange(of: now).start

        let todayExpense = active
            .filter { calendar.isDateInToday($0.occurredAt) && $0.kind == .expense }
            .reduce(0) { $0 + $1.amountCents }
        let todayIncome = active
            .filter { calendar.isDateInToday($0.occurredAt) && $0.kind == .income }
            .reduce(0) { $0 + $1.amountCents }

        let monthItems = active.filter { $0.occurredAt >= monthStart }
        let monthExpense = monthItems.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
        let monthIncome = monthItems.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }

        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        var grouped: [String: Int] = [:]
        for item in monthItems where item.kind == .expense {
            grouped[item.categoryName, default: 0] += item.amountCents
        }
        let slices = grouped
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { name, cents in
                CategorySlice(
                    name: name,
                    colorHex: categories.first(where: { $0.name == name })?.colorHex ?? "#9AA0A6",
                    amountCents: cents
                )
            }

        let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        let totalBudget = budgets
            .first(where: { $0.isTotalBudget && (($0.monthKey.isEmpty) || $0.monthKey == MonthKey.string(for: now)) })
            .map(\.amountCents) ?? 0

        let last = active.max { $0.occurredAt < $1.occurredAt }

        let snapshot = Snapshot(
            updatedAt: now,
            todayExpenseCents: todayExpense,
            todayIncomeCents: todayIncome,
            monthExpenseCents: monthExpense,
            monthIncomeCents: monthIncome,
            monthBudgetCents: totalBudget,
            monthKey: MonthKey.string(for: now),
            topCategories: slices,
            lastTransactionTitle: last?.displayTitle ?? "",
            lastTransactionAmountCents: last?.amountCents ?? 0,
            lastTransactionTime: last?.occurredAt ?? now
        )
        write(snapshot)
    }

    static func write(_ snapshot: Snapshot) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
        // 记账后立即刷新桌面小组件
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> Snapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }
}
