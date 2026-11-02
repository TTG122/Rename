//
//  StatsView.swift
//  简记
//
//  图表与月度总结。所有数字都来自本地 SwiftData，AI 总结是模板化生成，
//  不调用任何云端模型（除非用户在设置里主动开启，本期默认关闭）。
//

import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router

    @Query private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query private var budgets: [Budget]

    @State private var selectedMonth: Date = MonthKey.monthRange(of: .now).start
    @State private var sharePayload: SharePayload?
    @State private var isExporting = false
    @State private var exportError: String?

    private var report: MonthlyReport {
        MonthlyReportBuilder.build(
            month: selectedMonth,
            transactions: transactions,
            categories: categories,
            budgets: budgets
        )
    }

    private var dailyPoints: [(day: Int, expense: Int, income: Int)] {
        let range = MonthKey.monthRange(of: selectedMonth)
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: range.start)?.count ?? 30
        var expense = [Int](repeating: 0, count: days + 1)
        var income = [Int](repeating: 0, count: days + 1)

        for item in transactions where !item.isDeleted {
            guard item.occurredAt >= range.start, item.occurredAt < range.end else { continue }
            let day = calendar.component(.day, from: item.occurredAt)
            guard day >= 1, day <= days else { continue }
            if item.kind == .expense { expense[day] += item.amountCents }
            else { income[day] += item.amountCents }
        }
        return (1...days).map { (day: $0, expense: expense[$0], income: income[$0]) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthSelector
                    overviewCard
                    trendCard
                    categoryCard
                    rankingCard
                    budgetCard
                    comparisonCard
                    aiSummaryCard
                    if !report.subscriptions.isEmpty { subscriptionCard }
                    if !report.anomalies.isEmpty { anomalyCard }
                    exportCard
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, 32)
            }
            .background(Theme.background)
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $sharePayload) { payload in
                ActivityView(items: payload.items)
                    .presentationDetents([.medium, .large])
            }
            .alert("导出失败", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("好", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    // MARK: - 月份选择

    private var monthSelector: some View {
        HStack {
            Button {
                selectedMonth = MonthKey.previousMonth(of: selectedMonth)
                Haptics.selection()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(MonthKey.displayTitle(for: selectedMonth))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Button {
                let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                if next <= MonthKey.monthRange(of: .now).start {
                    selectedMonth = next
                    Haptics.selection()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(canGoNext ? 1 : 0.3)
        }
        .padding(.top, 4)
    }

    private var canGoNext: Bool {
        let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        return next <= MonthKey.monthRange(of: .now).start
    }

    // MARK: - 概览

    private var overviewCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("总支出")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    MoneyText(cents: report.totalExpenseCents, kind: .expense, size: 34)
                }
                Spacer()
                if report.previousMonthExpenseCents > 0 {
                    changeBadge
                }
            }

            HStack(spacing: 0) {
                StatTile(title: "总收入", value: "¥\(MoneyFormatter.grouped(cents: report.totalIncomeCents))", tint: Theme.income)
                Divider().frame(height: 30).padding(.horizontal, 10)
                StatTile(title: "结余", value: "¥\(MoneyFormatter.grouped(cents: report.balanceCents))", tint: report.balanceCents >= 0 ? Theme.income : Theme.expense)
                Divider().frame(height: 30).padding(.horizontal, 10)
                StatTile(title: "日均", value: "¥\(MoneyFormatter.grouped(cents: report.dailyAverageCents))", tint: Theme.textPrimary)
            }

            if report.maxExpenseCents > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("最大一笔：\(report.maxExpenseTitle) ¥\(MoneyFormatter.grouped(cents: report.maxExpenseCents))（\(report.maxExpenseCategory)）")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
            }
        }
        .cardStyle(radius: 20, padding: 18)
    }

    private var changeBadge: some View {
        let ratio = report.expenseChangeRatio
        let isUp = ratio >= 0
        return HStack(spacing: 3) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
            Text("\(Int(abs(ratio) * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(isUp ? Theme.expense : Theme.income)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background((isUp ? Theme.expense : Theme.income).opacity(0.1), in: Capsule())
    }

    // MARK: - 趋势

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "每日收支趋势", subtitle: "柱状为支出，折线为收入")

            Chart {
                ForEach(dailyPoints, id: \.day) { point in
                    BarMark(
                        x: .value("日", point.day),
                        y: .value("支出", Double(point.expense) / 100)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.expense.opacity(0.85), Theme.expense.opacity(0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(3)

                    LineMark(
                        x: .value("日", point.day),
                        y: .value("收入", Double(point.income) / 100)
                    )
                    .foregroundStyle(Theme.income)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 170)
            .chartXAxis {
                AxisMarks(values: .stride(by: 5)) { value in
                    AxisValueLabel {
                        if let day = value.as(Int.self) {
                            Text("\(day)日").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Theme.separator)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text("\(Int(amount))").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
        }
        .cardStyle(radius: 20, padding: 16)
    }

    // MARK: - 分类

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "分类占比", subtitle: "共 \(report.categoryBreakdown.count) 个分类")

            if report.categoryBreakdown.isEmpty {
                EmptyStateView(symbol: "chart.bar", title: "本月还没有支出")
            } else {
                Chart(report.categoryBreakdown.prefix(8), id: \.name) { stat in
                    BarMark(
                        x: .value("金额", Double(stat.amountCents) / 100),
                        y: .value("分类", stat.name)
                    )
                    .foregroundStyle(Color(hex: stat.colorHex) ?? Theme.expense)
                    .cornerRadius(6)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(Int(stat.ratio * 100))%")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: CGFloat(min(report.categoryBreakdown.count, 8)) * 32 + 20)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .cardStyle(radius: 20, padding: 16)
    }

    // MARK: - 排行

    private var rankingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "消费排行", subtitle: "按分类金额排序")

            if report.categoryBreakdown.isEmpty {
                EmptyStateView(symbol: "list.number", title: "暂无数据")
            } else {
                ForEach(Array(report.categoryBreakdown.enumerated()), id: \.element.name) { index, stat in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(index < 3 ? Theme.brand : Theme.textTertiary)
                            .frame(width: 18)

                        Image(systemName: stat.symbolName)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: stat.colorHex) ?? Theme.expense)
                            .frame(width: 18)

                        Text(stat.name)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textPrimary)

                        Spacer()

                        Text("\(stat.count) 笔")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)

                        Text("¥\(MoneyFormatter.grouped(cents: stat.amountCents))")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 92, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .cardStyle(radius: 20, padding: 16)
    }

    // MARK: - 预算

    @ViewBuilder
    private var budgetCard: some View {
        if report.budgetCents > 0 {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "预算使用", subtitle: "总预算 ¥\(MoneyFormatter.grouped(cents: report.budgetCents))")

                BudgetProgressBar(
                    progress: min(report.budgetProgress, 1),
                    tint: report.isBudgetExceeded ? Theme.expense : Theme.brand,
                    height: 10
                )

                HStack {
                    Text("已用 ¥\(MoneyFormatter.grouped(cents: report.totalExpenseCents))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if report.isBudgetExceeded {
                        Text("超出 ¥\(MoneyFormatter.grouped(cents: report.totalExpenseCents - report.budgetCents))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.expense)
                    } else {
                        Text("还剩 ¥\(MoneyFormatter.grouped(cents: report.budgetRemainingCents))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.income)
                    }
                }
            }
            .cardStyle(radius: 20, padding: 16)
        }
    }

    // MARK: - 对比

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "与上月对比")

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("上月")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Text("¥\(MoneyFormatter.grouped(cents: report.previousMonthExpenseCents))")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("本月")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Text("¥\(MoneyFormatter.grouped(cents: report.totalExpenseCents))")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.expense)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("变化")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Text(changeText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(report.expenseChangeRatio >= 0 ? Theme.expense : Theme.income)
                }
            }

            if report.previousMonthExpenseCents == 0 {
                Text("上个月没有记录，下个月就能看到对比了")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .cardStyle(radius: 20, padding: 16)
    }

    private var changeText: String {
        guard report.previousMonthExpenseCents > 0 else { return "—" }
        let percent = Int(abs(report.expenseChangeRatio) * 100)
        return (report.expenseChangeRatio >= 0 ? "+" : "-") + "\(percent)%"
    }

    // MARK: - AI 总结

    private var aiSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.brand)
                Text("本月小结")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("本机生成")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.background, in: Capsule())
            }

            Text(report.summaryText)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Theme.textPrimary)

            if !report.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("可以试试")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(Array(report.suggestions.enumerated()), id: \.offset) { index, suggestion in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Theme.brand, in: Circle())
                            Text(suggestion)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .cardStyle(radius: 20, padding: 16)
    }

    // MARK: - 订阅

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "疑似连续订阅", subtitle: "每月固定支出，值得看一眼")
            ForEach(report.subscriptions) { item in
                HStack {
                    Image(systemName: "repeat")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.brand)
                    Text(item.name)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(item.categoryName)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                    Text("¥\(MoneyFormatter.grouped(cents: item.amountCents))")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.vertical, 3)
            }
        }
        .cardStyle(radius: 20, padding: 16)
    }

    // MARK: - 异常

    private var anomalyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "异常消费提醒", subtitle: "单笔明显高于同分类平均")
            ForEach(report.anomalies) { anomaly in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(anomaly.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(anomaly.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text("¥\(MoneyFormatter.grouped(cents: anomaly.amountCents))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.expense)
                }
                .padding(.vertical, 3)
            }
        }
        .cardStyle(radius: 20, padding: 16)
    }

    // MARK: - 导出

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "导出与分享", subtitle: "全部在本机生成，不上传")

            HStack(spacing: 10) {
                exportButton(title: "长图", symbol: "photo") {
                    exportLongImage()
                }
                exportButton(title: "PDF", symbol: "doc.richtext") {
                    exportPDF()
                }
                exportButton(title: "CSV", symbol: "tablecells") {
                    exportCSV()
                }
                exportButton(title: "Excel", symbol: "doc.text") {
                    exportExcel()
                }
            }
        }
        .cardStyle(radius: 20, padding: 16)
    }

    private func exportButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 导出动作

    private func monthTransactions() -> [Transaction] {
        let range = MonthKey.monthRange(of: selectedMonth)
        return transactions.filter {
            !$0.isDeleted && $0.occurredAt >= range.start && $0.occurredAt < range.end
        }
    }

    private func exportCSV() {
        do {
            let url = try ExportService.exportCSVFile(transactions: monthTransactions())
            sharePayload = SharePayload(items: [url])
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportExcel() {
        do {
            let url = try ExportService.exportXLSXFile(transactions: monthTransactions())
            sharePayload = SharePayload(items: [url])
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportPDF() {
        do {
            let url = try ExportService.exportPDFFile(report: report)
            sharePayload = SharePayload(items: [url])
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportLongImage() {
        guard let image = ExportService.longImage(ReportShareCard(report: report, categories: categories)) else {
            exportError = "长图渲染失败，请稍后重试"
            return
        }
        do {
            let url = try ExportService.saveLongImageToTemporary(image)
            sharePayload = SharePayload(items: [url, "来自简记的 \(report.monthTitle)月报"])
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - 长图卡片

struct ReportShareCard: View {
    let report: MonthlyReport
    let categories: [Category]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("简记")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                    Text("\(report.monthTitle)消费月报")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.brand)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("总支出")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text("¥\(MoneyFormatter.grouped(cents: report.totalExpenseCents))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.expense)
                Text("收入 ¥\(MoneyFormatter.grouped(cents: report.totalIncomeCents)) · 结余 ¥\(MoneyFormatter.grouped(cents: report.balanceCents)) · 日均 ¥\(MoneyFormatter.grouped(cents: report.dailyAverageCents))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("分类排行")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(report.categoryBreakdown.prefix(6), id: \.name) { stat in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: stat.colorHex) ?? Theme.expense)
                            .frame(width: 6, height: 6)
                        Text(stat.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("¥\(MoneyFormatter.grouped(cents: stat.amountCents))")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(Int(stat.ratio * 100))%")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("本月小结")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(report.summaryText)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("由简记生成 · 数据只在本机")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(22)
        .frame(width: 390, alignment: .leading)
        .background(Theme.background)
    }
}
