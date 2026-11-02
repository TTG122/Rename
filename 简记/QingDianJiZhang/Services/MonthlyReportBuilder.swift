//
//  MonthlyReportBuilder.swift
//  轻点记账
//
//  月度总结计算器。纯本地计算，不依赖任何网络。
//  「AI 总结」是基于真实数字的模板化生成——不做假数据、不编造数字。
//

import Foundation

// MARK: - 报表模型

struct CategoryStat: Identifiable {
    var id: String { name }
    let name: String
    let colorHex: String
    let symbolName: String
    let amountCents: Int
    let count: Int
    /// 占总支出的比例 0...1
    let ratio: Double
}

struct WeekBucket: Identifiable {
    var id: Int { index }
    let index: Int
    let label: String
    let expenseCents: Int
    let incomeCents: Int
}

struct MerchantStat: Identifiable {
    var id: String { name }
    let name: String
    let amountCents: Int
    let count: Int
}

struct FixedExpenseStat: Identifiable {
    var id: String { name }
    let name: String
    let amountCents: Int
    let count: Int
    let categoryName: String
}

struct SubscriptionStat: Identifiable {
    var id: String { name }
    let name: String
    let amountCents: Int
    let categoryName: String
    let lastDate: Date
}

struct SpendingAnomaly: Identifiable {
    var id: UUID { transactionID }
    let transactionID: UUID
    let title: String
    let detail: String
    let amountCents: Int
}

struct MonthlyReport {
    let monthKey: String
    let monthTitle: String
    let startDate: Date
    let endDate: Date

    let totalIncomeCents: Int
    let totalExpenseCents: Int
    let balanceCents: Int
    let dailyAverageCents: Int
    let transactionCount: Int

    let maxExpenseTitle: String
    let maxExpenseCents: Int
    let maxExpenseCategory: String

    let categoryBreakdown: [CategoryStat]
    let weeklyTrend: [WeekBucket]
    let previousMonthExpenseCents: Int
    let expenseChangeRatio: Double

    let budgetCents: Int
    let budgetProgress: Double

    let topMerchants: [MerchantStat]
    let fixedExpenses: [FixedExpenseStat]
    let subscriptions: [SubscriptionStat]
    let anomalies: [SpendingAnomaly]

    let summaryText: String
    let suggestions: [String]
    let healthScore: Int

    var isEmpty: Bool { transactionCount == 0 }
    var budgetRemainingCents: Int { max(0, budgetCents - totalExpenseCents) }
    var isBudgetExceeded: Bool { budgetCents > 0 && totalExpenseCents > budgetCents }
}

// MARK: - 构建

enum MonthlyReportBuilder {

    static func build(
        month: Date,
        transactions: [Transaction],
        categories: [Category],
        budgets: [Budget],
        calendar: Calendar = .current
    ) -> MonthlyReport {
        let range = MonthKey.monthRange(of: month, calendar: calendar)
        let previousRange = MonthKey.monthRange(of: MonthKey.previousMonth(of: month, calendar: calendar), calendar: calendar)

        let active = transactions.filter { !$0.isDeleted }
        let current = active.filter { $0.occurredAt >= range.start && $0.occurredAt < range.end }
        let previous = active.filter { $0.occurredAt >= previousRange.start && $0.occurredAt < previousRange.end }

        let expenseItems = current.filter { $0.kind == .expense }
        let incomeItems = current.filter { $0.kind == .income }

        let totalExpense = expenseItems.reduce(0) { $0 + $1.amountCents }
        let totalIncome = incomeItems.reduce(0) { $0 + $1.amountCents }
        let previousExpense = previous.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }

        // 日均：按「已经过去的天数」算，本月还没过完时不要把未来的天算进去
        let daysInMonth = calendar.range(of: .day, in: .month, for: range.start)?.count ?? 30
        let isCurrentMonth = calendar.isDate(range.start, equalTo: MonthKey.monthRange(of: .now).start, toGranularity: .month)
        let today = calendar.component(.day, from: .now)
        let effectiveDays = isCurrentMonth ? max(today, 1) : daysInMonth
        let dailyAverage = totalExpense / effectiveDays

        // 分类占比
        let breakdown = categoryBreakdown(
            items: expenseItems,
            total: totalExpense,
            categories: categories
        )

        // 周趋势
        let weeks = weeklyTrend(items: current, monthStart: range.start, calendar: calendar)

        // 最大一笔
        let maxItem = expenseItems.max { $0.amountCents < $1.amountCents }

        // 预算
        let monthKey = MonthKey.string(for: month)
        let totalBudget = budgets
            .first(where: { $0.isTotalBudget && ($0.monthKey == monthKey || $0.monthKey.isEmpty) })
            .map(\.amountCents) ?? 0

        // 商户 / 固定支出 / 订阅
        let merchants = topMerchants(items: expenseItems)
        let fixed = fixedExpenses(items: expenseItems)
        let subs = subscriptions(current: expenseItems, previous: previous, calendar: calendar)

        // 异常消费
        let anomalies = findAnomalies(items: expenseItems, breakdown: breakdown)

        let changeRatio: Double = previousExpense > 0
            ? Double(totalExpense - previousExpense) / Double(previousExpense)
            : 0

        let health = healthScore(
            totalExpense: totalExpense,
            budget: totalBudget,
            changeRatio: changeRatio,
            subscriptions: subs.count,
            anomalies: anomalies.count
        )

        let summary = makeSummary(
            month: month,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            previousExpense: previousExpense,
            changeRatio: changeRatio,
            breakdown: breakdown,
            maxItem: maxItem,
            transactionCount: current.count
        )

        let suggestions = makeSuggestions(
            totalExpense: totalExpense,
            budget: totalBudget,
            breakdown: breakdown,
            previousExpense: previousExpense,
            subscriptions: subs,
            anomalies: anomalies
        )

        return MonthlyReport(
            monthKey: monthKey,
            monthTitle: MonthKey.displayTitle(for: month),
            startDate: range.start,
            endDate: range.end,
            totalIncomeCents: totalIncome,
            totalExpenseCents: totalExpense,
            balanceCents: totalIncome - totalExpense,
            dailyAverageCents: dailyAverage,
            transactionCount: current.count,
            maxExpenseTitle: maxItem?.displayTitle ?? "—",
            maxExpenseCents: maxItem?.amountCents ?? 0,
            maxExpenseCategory: maxItem?.categoryName ?? "—",
            categoryBreakdown: breakdown,
            weeklyTrend: weeks,
            previousMonthExpenseCents: previousExpense,
            expenseChangeRatio: changeRatio,
            budgetCents: totalBudget,
            budgetProgress: totalBudget > 0 ? min(Double(totalExpense) / Double(totalBudget), 3.0) : 0,
            topMerchants: merchants,
            fixedExpenses: fixed,
            subscriptions: subs,
            anomalies: anomalies,
            summaryText: summary,
            suggestions: suggestions,
            healthScore: health
        )
    }

    // MARK: - 分类

    private static func categoryBreakdown(
        items: [Transaction],
        total: Int,
        categories: [Category]
    ) -> [CategoryStat] {
        var grouped: [String: (cents: Int, count: Int)] = [:]
        for item in items {
            let key = item.categoryName.isEmpty ? "其他" : item.categoryName
            var current = grouped[key] ?? (0, 0)
            current.cents += item.amountCents
            current.count += 1
            grouped[key] = current
        }

        return grouped
            .map { name, value in
                let category = categories.first { $0.name == name }
                return CategoryStat(
                    name: name,
                    colorHex: category?.colorHex ?? "#9AA0A6",
                    symbolName: category?.symbolName ?? "ellipsis.circle.fill",
                    amountCents: value.cents,
                    count: value.count,
                    ratio: total > 0 ? Double(value.cents) / Double(total) : 0
                )
            }
            .sorted { $0.amountCents > $1.amountCents }
    }

    // MARK: - 周趋势

    private static func weeklyTrend(items: [Transaction], monthStart: Date, calendar: Calendar) -> [WeekBucket] {
        var buckets: [WeekBucket] = []
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let weekCount = Int(ceil(Double(daysInMonth) / 7.0))

        for index in 0..<weekCount {
            let startDay = index * 7
            let endDay = min(startDay + 7, daysInMonth)
            var expense = 0
            var income = 0
            for item in items {
                let day = calendar.component(.day, from: item.occurredAt)
                guard day >= startDay + 1, day <= endDay else { continue }
                if item.kind == .expense { expense += item.amountCents } else { income += item.amountCents }
            }
            buckets.append(
                WeekBucket(
                    index: index,
                    label: "\(startDay + 1)-\(endDay)日",
                    expenseCents: expense,
                    incomeCents: income
                )
            )
        }
        return buckets
    }

    // MARK: - 商户排行

    private static func topMerchants(items: [Transaction], limit: Int = 6) -> [MerchantStat] {
        var grouped: [String: (cents: Int, count: Int)] = [:]
        for item in items {
            let name = item.merchant.isEmpty ? item.displayTitle : item.merchant
            guard !name.isEmpty else { continue }
            var current = grouped[name] ?? (0, 0)
            current.cents += item.amountCents
            current.count += 1
            grouped[name] = current
        }
        return grouped
            .map { MerchantStat(name: $0.key, amountCents: $0.value.cents, count: $0.value.count) }
            .sorted { $0.amountCents > $1.amountCents }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 固定支出

    /// 同一商户本月出现 ≥3 次且金额波动 < 12% → 视为固定支出
    private static func fixedExpenses(items: [Transaction]) -> [FixedExpenseStat] {
        var grouped: [String: [Transaction]] = [:]
        for item in items {
            let name = item.merchant.trimmingCharacters(in: .whitespaces)
            guard name.count >= 2 else { continue }
            grouped[name, default: []].append(item)
        }

        return grouped
            .compactMap { name, list -> FixedExpenseStat? in
                guard list.count >= 3 else { return nil }
                let amounts = list.map(\.amountCents).sorted()
                let median = amounts[amounts.count / 2]
                guard median > 0 else { return nil }
                let maxDeviation = amounts.map { abs($0 - median) }.max() ?? 0
                guard Double(maxDeviation) / Double(median) < 0.12 else { return nil }
                return FixedExpenseStat(
                    name: name,
                    amountCents: median,
                    count: list.count,
                    categoryName: list.first?.categoryName ?? "其他"
                )
            }
            .sorted { $0.amountCents > $1.amountCents }
    }

    // MARK: - 重复订阅

    /// 上个月和这个月都出现、金额接近的商户 → 大概率是订阅
    private static func subscriptions(
        current: [Transaction],
        previous: [Transaction],
        calendar: Calendar
    ) -> [SubscriptionStat] {
        let subscriptionKeywords = ["会员", "订阅", "连续包月", "年费", "包月", "vip", "supercell", "icloud"]

        var result: [SubscriptionStat] = []
        var groupedCurrent: [String: [Transaction]] = [:]
        for item in current {
            let name = item.merchant.trimmingCharacters(in: .whitespaces)
            guard name.count >= 2 else { continue }
            groupedCurrent[name, default: []].append(item)
        }

        var groupedPrevious: [String: [Transaction]] = [:]
        for item in previous where item.kind == .expense {
            let name = item.merchant.trimmingCharacters(in: .whitespaces)
            groupedPrevious[name, default: []].append(item)
        }

        for (name, list) in groupedCurrent {
            guard let latest = list.max(by: { $0.occurredAt < $1.occurredAt }) else { continue }
            let isKeywordHit = subscriptionKeywords.contains {
                TextNormalizer.normalize(name).contains(TextNormalizer.normalize($0))
            }
            let previousList = groupedPrevious[name] ?? []
            let hasPrevious = previousList.contains { previousItem in
                let deviation = abs(previousItem.amountCents - latest.amountCents)
                return Double(deviation) <= Double(max(latest.amountCents, 1)) * 0.1
            }

            if isKeywordHit || hasPrevious {
                result.append(
                    SubscriptionStat(
                        name: name,
                        amountCents: latest.amountCents,
                        categoryName: latest.categoryName,
                        lastDate: latest.occurredAt
                    )
                )
            }
        }
        return result.sorted { $0.amountCents > $1.amountCents }
    }

    // MARK: - 异常消费

    /// 单笔超过同分类平均值 3 倍且 ≥ 200 元
    private static func findAnomalies(items: [Transaction], breakdown: [CategoryStat]) -> [SpendingAnomaly] {
        var result: [SpendingAnomaly] = []
        for stat in breakdown where stat.count >= 2 {
            let average = stat.amountCents / stat.count
            guard average > 0 else { continue }
            for item in items where item.categoryName == stat.name {
                guard item.amountCents >= average * 3, item.amountCents >= 20_000 else { continue }
                result.append(
                    SpendingAnomaly(
                        transactionID: item.id,
                        title: "\(stat.name)有一笔异常支出",
                        detail: "比\(stat.name)的平均单笔高 \(Int(Double(item.amountCents) / Double(average))) 倍",
                        amountCents: item.amountCents
                    )
                )
            }
        }
        return result.sorted { $0.amountCents > $1.amountCents }.prefix(3).map { $0 }
    }

    // MARK: - 健康分

    private static func healthScore(
        totalExpense: Int,
        budget: Int,
        changeRatio: Double,
        subscriptions: Int,
        anomalies: Int
    ) -> Int {
        var score = 85
        if budget > 0 {
            let usage = Double(totalExpense) / Double(budget)
            if usage > 1.2 { score -= 25 }
            else if usage > 1.0 { score -= 15 }
            else if usage < 0.7 { score += 8 }
        }
        if changeRatio > 0.3 { score -= 12 }
        else if changeRatio < -0.15 { score += 6 }
        if subscriptions >= 4 { score -= 8 }
        score -= min(anomalies * 4, 12)
        return min(max(score, 40), 99)
    }

    // MARK: - 总结文案

    private static func makeSummary(
        month: Date,
        totalExpense: Int,
        totalIncome: Int,
        previousExpense: Int,
        changeRatio: Double,
        breakdown: [CategoryStat],
        maxItem: Transaction?,
        transactionCount: Int
    ) -> String {
        guard transactionCount > 0 else {
            return "这个月还没有记账记录。双击手机背面，试一笔看看？"
        }

        var sentences: [String] = []
        let expenseText = MoneyFormatter.compact(cents: totalExpense)

        if previousExpense > 0 {
            let direction = changeRatio >= 0 ? "增加" : "减少"
            let percent = Int(abs(changeRatio) * 100)
            sentences.append("本月共支出 \(expenseText) 元，比上月\(direction) \(percent)%。")
        } else {
            sentences.append("本月共支出 \(expenseText) 元。")
        }

        if let top = breakdown.first {
            sentences.append("\(top.name)支出最高，共 \(MoneyFormatter.compact(cents: top.amountCents)) 元，占比 \(Int(top.ratio * 100))%。")
        }

        if breakdown.count >= 2 {
            let second = breakdown[1]
            sentences.append("其次是\(second.name)，\(MoneyFormatter.compact(cents: second.amountCents)) 元。")
        }

        if let maxItem {
            sentences.append("最大一笔是「\(maxItem.displayTitle)」\(MoneyFormatter.compact(cents: maxItem.amountCents)) 元。")
        }

        if totalIncome > 0 {
            sentences.append("本月收入 \(MoneyFormatter.compact(cents: totalIncome)) 元，结余 \(MoneyFormatter.compact(cents: totalIncome - totalExpense)) 元。")
        }

        return sentences.joined()
    }

    // MARK: - 节省建议

    private static func makeSuggestions(
        totalExpense: Int,
        budget: Int,
        breakdown: [CategoryStat],
        previousExpense: Int,
        subscriptions: [SubscriptionStat],
        anomalies: [SpendingAnomaly]
    ) -> [String] {
        var suggestions: [String] = []

        if budget > 0, totalExpense > budget {
            let over = totalExpense - budget
            suggestions.append("本月已超预算 \(MoneyFormatter.compact(cents: over)) 元，下个月先把非必要支出压下来。")
        } else if budget > 0 {
            let usage = Int(Double(totalExpense) / Double(budget) * 100)
            if usage < 80 {
                suggestions.append("预算只用了 \(usage)%，节奏不错，按这个走。")
            }
        }

        // 找环比增长最快的分类
        if let top = breakdown.first, top.ratio > 0.35 {
            let target = top.amountCents * 7 / 10
            suggestions.append("\(top.name)占了 \(Int(top.ratio * 100))%，建议下个月控制在 \(MoneyFormatter.compact(cents: target)) 元以内。")
        }

        if let game = breakdown.first(where: { $0.name == "游戏" }), game.amountCents > 30_000 {
            let target = min(game.amountCents, 50_000)
            suggestions.append("游戏消费 \(MoneyFormatter.compact(cents: game.amountCents)) 元，建议设置 \(MoneyFormatter.compact(cents: target)) 元的月度上限。")
        }

        if subscriptions.count >= 3 {
            let total = subscriptions.reduce(0) { $0 + $1.amountCents }
            suggestions.append("检测到 \(subscriptions.count) 项疑似连续订阅，合计 \(MoneyFormatter.compact(cents: total)) 元，可以看看有哪些其实用不上。")
        }

        if !anomalies.isEmpty {
            suggestions.append("有 \(anomalies.count) 笔金额明显偏高的支出，点开看看是不是记错了。")
        }

        if previousExpense > 0 {
            let delta = totalExpense - previousExpense
            if delta > 0, delta > previousExpense / 5 {
                suggestions.append("本月比上月多花了 \(MoneyFormatter.compact(cents: delta)) 元，主要来自\(breakdown.first?.name ?? "日常消费")。")
            }
        }

        if suggestions.isEmpty {
            suggestions.append("记录得挺稳，继续保持每天看一眼的习惯就好。")
        }
        return Array(suggestions.prefix(4))
    }
}
