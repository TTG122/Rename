//
//  HomeView.swift
//  简记
//
//  首页目标：3 秒内看懂本月花了多少钱。
//  信息优先级：本月支出 → 结余 → 预算 → 今日 → 分类占比 → 最近账单。
//

import SwiftUI
import SwiftData
import Charts
import UIKit

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Transaction.occurredAt, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query private var budgets: [Budget]

    @State private var quickEntry: QuickEntryMode?
    @State private var showVoice = false
    @State private var showPhotoPicker = false

    private var activeTransactions: [Transaction] { transactions.filter { !$0.isDeleted } }

    private var monthStart: Date { MonthKey.monthRange(of: .now).start }

    private var monthItems: [Transaction] {
        activeTransactions.filter { $0.occurredAt >= monthStart }
    }

    private var monthExpense: Int {
        monthItems.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
    }

    private var monthIncome: Int {
        monthItems.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }
    }

    private var todayExpense: Int {
        let calendar = Calendar.current
        return activeTransactions
            .filter { calendar.isDateInToday($0.occurredAt) && $0.kind == .expense }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var monthBudget: Int {
        budgets
            .first(where: { $0.isTotalBudget && ($0.monthKey.isEmpty || $0.monthKey == MonthKey.string(for: .now)) })?
            .amountCents ?? 0
    }

    /// 分类占比为空时的提示：区分「本月没记账」和「账记在上个月」
    private var monthEmptyHint: String {
        guard let latest = activeTransactions.first else {
            return "双击手机背面记第一笔吧"
        }
        if latest.occurredAt >= monthStart {
            return "本月只记了收入，支出会在这里统计"
        }
        return "最近的记录在 \(MonthKey.displayTitle(for: latest.occurredAt))，去账单页能看到"
    }

    private var categorySlices: [CategoryStat] {
        var grouped: [String: Int] = [:]
        for item in monthItems where item.kind == .expense {
            grouped[item.categoryName, default: 0] += item.amountCents
        }
        let total = grouped.values.reduce(0, +)
        return grouped
            .map { name, cents in
                let category = categories.first { $0.name == name }
                return CategoryStat(
                    name: name,
                    colorHex: category?.colorHex ?? "#9AA0A6",
                    symbolName: category?.symbolName ?? "ellipsis.circle.fill",
                    amountCents: cents,
                    count: 0,
                    ratio: total > 0 ? Double(cents) / Double(total) : 0
                )
            }
            .sorted { $0.amountCents > $1.amountCents }
    }

    private var recentTransactions: [Transaction] {
        Array(activeTransactions.prefix(5))
    }

    private var backTapCount: Int {
        activeTransactions.filter { $0.source == .backTap }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    topBar
                    monthCard
                    quickActions
                    backTapStatusCard
                    todayRow
                    categoryCard
                    recentCard
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, 32)
            }
            .background(Theme.background)
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $quickEntry) { mode in
                TransactionEditorView(mode: mode)
                    .environment(router)
            }
            .sheet(isPresented: $showVoice) {
                VoiceRecordView()
                    .environment(router)
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoImportPicker { images in
                    Task { await handleImported(images) }
                }
            }
        }
    }

    // MARK: - 顶部

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Text(MonthKey.displayTitle(for: .now))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Button {
                Haptics.impact(.light)
                showVoice = true
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 40, height: 40)
                    .background(Theme.brandSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("语音记账")
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    // MARK: - 本月卡片

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本月支出")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    MoneyText(cents: monthExpense, kind: .expense, size: 38)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("结余")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Text("¥\(MoneyFormatter.grouped(cents: monthIncome - monthExpense))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(monthIncome - monthExpense >= 0 ? Theme.income : Theme.expense)
                }
            }

            HStack(spacing: 0) {
                StatTile(title: "本月收入", value: "¥\(MoneyFormatter.grouped(cents: monthIncome))", tint: Theme.income, symbol: "arrow.down.left")
                Divider().frame(height: 30).padding(.horizontal, 12)
                StatTile(title: "今日支出", value: "¥\(MoneyFormatter.grouped(cents: todayExpense))", tint: Theme.textPrimary, symbol: "sun.max")
                Divider().frame(height: 30).padding(.horizontal, 12)
                StatTile(title: "共记", value: "\(monthItems.count) 笔", tint: Theme.textPrimary, symbol: "list.bullet")
            }

            if monthBudget > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("预算 ¥\(MoneyFormatter.grouped(cents: monthBudget))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("已用 \(Int(min(Double(monthExpense) / Double(monthBudget), 9.99) * 100))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(progressTint)
                    }
                    BudgetProgressBar(
                        progress: min(Double(monthExpense) / Double(max(monthBudget, 1)), 1),
                        tint: progressTint
                    )
                }
            }
        }
        .cardStyle(radius: 20, padding: 18)
    }

    private var progressTint: Color {
        guard monthBudget > 0 else { return Theme.brand }
        let usage = Double(monthExpense) / Double(monthBudget)
        if usage > 1 { return Theme.expense }
        if usage > 0.85 { return .orange }
        return Theme.brand
    }

    // MARK: - 快捷入口

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.impact(.light)
                quickEntry = .expense
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("记一笔")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            quickActionButton(symbol: "photo.on.rectangle", title: "截图") {
                showPhotoPicker = true
            }
            quickActionButton(symbol: "doc.viewfinder", title: "小票") {
                showPhotoPicker = true
            }
            quickActionButton(symbol: "waveform", title: "语音") {
                showVoice = true
            }
        }
    }

    private func quickActionButton(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 58, height: 50)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 双击背面状态

    private var backTapStatusCard: some View {
        Button {
            router.showOnboarding = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 38, height: 38)
                    .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("双击背面记账")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(backTapCount > 0
                         ? "已经用过 \(backTapCount) 次，继续双击手机背面就行"
                         : "还没配置？30 秒设置一次，以后双击就记账")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .cardStyle(radius: 16, padding: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 今日

    private var todayRow: some View {
        Group {
            if todayExpense > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text("今天已经花了 ¥\(MoneyFormatter.grouped(cents: todayExpense))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: - 分类占比

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "分类占比", subtitle: MonthKey.displayTitle(for: .now), actionTitle: "看月报") {
                router.selectedTab = .stats
            }

            if categorySlices.isEmpty {
                EmptyStateView(symbol: "chart.pie", title: "本月还没有支出", message: monthEmptyHint)
            } else {
                HStack(spacing: 18) {
                    Chart(categorySlices.prefix(5), id: \.name) { slice in
                        SectorMark(
                            angle: .value("金额", slice.amountCents),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .cornerRadius(4)
                        .foregroundStyle(Color(hex: slice.colorHex) ?? Theme.expense)
                    }
                    .frame(width: 108, height: 108)
                    .chartLegend(.hidden)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(categorySlices.prefix(4), id: \.name) { slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: slice.colorHex) ?? Theme.expense)
                                    .frame(width: 7, height: 7)
                                Text(slice.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text("¥\(MoneyFormatter.compact(cents: slice.amountCents))")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                                Text("\(Int(slice.ratio * 100))%")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(width: 34, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .cardStyle(radius: 20, padding: 16)
    }

    // MARK: - 最近账单

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "最近账单", actionTitle: "全部") {
                router.selectedTab = .ledger
            }

            if recentTransactions.isEmpty {
                EmptyStateView(symbol: "tray", title: "还没有账单", message: "记第一笔只需要一次点击")
            } else {
                VStack(spacing: 0) {
                    ForEach(recentTransactions) { item in
                        TransactionRow(transaction: item, category: categories.first { $0.name == item.categoryName })
                        if item.id != recentTransactions.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .cardStyle(radius: 20, padding: 16)
    }

    // MARK: - 导入处理

    private func handleImported(_ images: [UIImage]) async {
        guard let first = images.first, let data = first.pngData() else { return }
        let outcome = await CapturePipeline.process(
            imageData: data,
            source: .screenshot,
            context: modelContext,
            categories: categories
        )
        CapturePipeline.ingestAndRoute(outcome: outcome, context: modelContext)
    }
}

// MARK: - 快捷记账模式

enum QuickEntryMode: String, Identifiable {
    case expense
    case income

    var id: String { rawValue }

    var kind: TransactionKind { self == .expense ? .expense : .income }
}
