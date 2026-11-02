//
//  LedgerView.swift
//  轻点记账
//
//  账单列表：按日期分组、搜索、筛选、批量管理、左滑修改删除。
//

import SwiftUI
import SwiftData

struct LedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router

    @Query(sort: \Transaction.occurredAt, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var searchText = ""
    @State private var kindFilter: TransactionKind?
    @State private var categoryFilter: String?
    @State private var monthFilter: Date?
    @State private var editingTransaction: Transaction?
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()
    @State private var showBatchDeleteAlert = false
    @State private var showFilterSheet = false

    // MARK: - 过滤

    private var filtered: [Transaction] {
        var result = transactions.filter { !$0.isDeleted }

        if let kindFilter {
            result = result.filter { $0.kind == kindFilter }
        }
        if let categoryFilter {
            result = result.filter { $0.categoryName == categoryFilter }
        }
        if let monthFilter {
            let range = MonthKey.monthRange(of: monthFilter)
            result = result.filter { $0.occurredAt >= range.start && $0.occurredAt < range.end }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let keyword = searchText.trimmingCharacters(in: .whitespaces)
            result = result.filter { item in
                item.merchant.localizedCaseInsensitiveContains(keyword)
                || item.item.localizedCaseInsensitiveContains(keyword)
                || item.categoryName.localizedCaseInsensitiveContains(keyword)
                || item.note.localizedCaseInsensitiveContains(keyword)
                || MoneyFormatter.string(cents: item.amountCents).contains(keyword)
                || item.amountCents.description.contains(keyword)
            }
        }
        return result
    }

    private var grouped: [(date: Date, items: [Transaction])] {
        let calendar = Calendar.current
        let dictionary = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.occurredAt) }
        return dictionary
            .map { (date: $0.key, items: $0.value.sorted { $0.occurredAt > $1.occurredAt }) }
            .sorted { $0.date > $1.date }
    }

    private var totalExpense: Int {
        filtered.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
    }

    private var totalIncome: Int {
        filtered.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryBar
                filterBar

                if grouped.isEmpty {
                    Spacer()
                    if searchText.isEmpty {
                        EmptyStateView(
                            symbol: "tray",
                            title: "还没有账单",
                            message: "双击手机背面，2 秒记一笔"
                        )
                    } else {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "没有找到匹配的账单",
                            message: "换个关键词试试",
                            actionTitle: "清除搜索",
                            action: { searchText = "" }
                        )
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(grouped, id: \.date) { section in
                            Section {
                                ForEach(section.items) { item in
                                    row(for: item)
                                }
                            } header: {
                                DaySectionHeader(
                                    date: section.date,
                                    expenseCents: section.items.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents },
                                    incomeCents: section.items.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }
                                )
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                }
            }
            .background(Theme.background)
            .navigationTitle("账单")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "搜索商户、金额、分类、备注")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "完成" : "管理") {
                        withAnimation {
                            isSelecting.toggle()
                            if !isSelecting { selectedIDs.removeAll() }
                        }
                    }
                    .font(.system(size: 15, weight: isSelecting ? .semibold : .regular))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    batchBar
                }
            }
            .sheet(item: $editingTransaction) { item in
                TransactionEditorView(transaction: item)
                    .environment(router)
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheet(
                    kindFilter: $kindFilter,
                    categoryFilter: $categoryFilter,
                    monthFilter: $monthFilter,
                    categories: categories
                )
                .presentationDetents([.height(520)])
            }
            .alert("删除选中的 \(selectedIDs.count) 笔账单？", isPresented: $showBatchDeleteAlert) {
                Button("删除", role: .destructive) {
                    RecordService.delete(ids: Array(selectedIDs), in: modelContext)
                    selectedIDs.removeAll()
                    isSelecting = false
                    Haptics.success()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func row(for item: Transaction) -> some View {
        let category = categories.first { $0.name == item.categoryName }

        HStack(spacing: 10) {
            if isSelecting {
                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(selectedIDs.contains(item.id) ? Theme.brand : Theme.textTertiary)
            }
            TransactionRow(transaction: item, category: category)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                if selectedIDs.contains(item.id) {
                    selectedIDs.remove(item.id)
                } else {
                    selectedIDs.insert(item.id)
                }
                Haptics.selection()
            } else {
                editingTransaction = item
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                RecordService.delete(item, in: modelContext)
                Haptics.warning()
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                editingTransaction = item
            } label: {
                Label("修改", systemImage: "pencil")
            }
            .tint(Theme.brand)
        }
        .swipeActions(edge: .leading) {
            Button {
                duplicate(item)
            } label: {
                Label("再来一笔", systemImage: "plus.square.on.square")
            }
            .tint(.blue)
        }
    }

    // MARK: - 汇总条

    private var summaryBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("支出")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Text("¥\(MoneyFormatter.grouped(cents: totalExpense))")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.expense)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("收入")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Text("¥\(MoneyFormatter.grouped(cents: totalIncome))")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.income)
            }
            Spacer()
            Text("\(filtered.count) 笔")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, 10)
    }

    // MARK: - 筛选条

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "全部", isOn: kindFilter == nil && categoryFilter == nil && monthFilter == nil) {
                    kindFilter = nil
                    categoryFilter = nil
                    monthFilter = nil
                }
                filterChip(title: "支出", isOn: kindFilter == .expense) {
                    kindFilter = kindFilter == .expense ? nil : .expense
                }
                filterChip(title: "收入", isOn: kindFilter == .income) {
                    kindFilter = kindFilter == .income ? nil : .income
                }
                if let categoryFilter {
                    filterChip(title: categoryFilter, isOn: true) {
                        self.categoryFilter = nil
                    }
                }
                if let monthFilter {
                    filterChip(title: MonthKey.displayTitle(for: monthFilter), isOn: true) {
                        self.monthFilter = nil
                    }
                }
                Button {
                    showFilterSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text("更多筛选")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.brandSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, 8)
        }
    }

    private func filterChip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? .white : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isOn ? Theme.brand : Theme.card, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isOn ? Color.clear : Theme.stroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 批量条

    private var batchBar: some View {
        HStack(spacing: 12) {
            Button {
                if selectedIDs.count == filtered.count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(filtered.map(\.id))
                }
            } label: {
                Text(selectedIDs.count == filtered.count ? "取消全选" : "全选")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("已选 \(selectedIDs.count) 笔")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            Button {
                showBatchDeleteAlert = true
            } label: {
                Text("删除")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Theme.expense, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedIDs.isEmpty)
            .opacity(selectedIDs.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - 动作

    private func duplicate(_ item: Transaction) {
        var draft = TransactionDraft()
        draft.kind = item.kind
        draft.amountCents = item.amountCents
        draft.merchant = item.merchant
        draft.item = item.item
        draft.note = item.note
        draft.categoryName = item.categoryName
        draft.categoryID = item.categoryID
        draft.occurredAt = .now
        draft.platform = item.platform
        draft.account = item.account
        draft.source = .manual
        draft.confidence = 1.0

        let transaction = RecordService.save(draft: draft, in: modelContext, categories: categories)
        Haptics.success()
        AppRouter.shared.showSaved(transaction: transaction) {}
    }
}

// MARK: - 筛选面板

private struct FilterSheet: View {
    @Binding var kindFilter: TransactionKind?
    @Binding var categoryFilter: String?
    @Binding var monthFilter: Date?
    let categories: [Category]

    @Environment(\.dismiss) private var dismiss

    private var monthOptions: [Date] {
        (0..<12).compactMap { Calendar.current.date(byAdding: .month, value: -$0, to: .now) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("分类")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                            CategoryChip(name: "全部", symbolName: "square.grid.2x2", color: Theme.brand, isSelected: categoryFilter == nil) {
                                categoryFilter = nil
                            }
                            ForEach(categories) { category in
                                CategoryChip(
                                    name: category.name,
                                    symbolName: category.symbolName,
                                    color: category.color,
                                    isSelected: categoryFilter == category.name
                                ) {
                                    categoryFilter = categoryFilter == category.name ? nil : category.name
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("月份")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(monthOptions, id: \.self) { month in
                                let isOn = monthFilter.map { Calendar.current.isDate($0, equalTo: month, toGranularity: .month) } ?? false
                                Button {
                                    monthFilter = isOn ? nil : month
                                } label: {
                                    Text(MonthKey.displayTitle(for: month))
                                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                                        .foregroundStyle(isOn ? .white : Theme.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(isOn ? Theme.brand : Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(isOn ? Color.clear : Theme.stroke, lineWidth: 1)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    Button("完成") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(Theme.Spacing.page)
            }
            .background(Theme.background)
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
