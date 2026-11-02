//
//  CategoryManagerView.swift
//  简记
//
//  分类管理：系统分类 + 自定义分类 + 商户规则 + 历史学习记录。
//

import SwiftUI
import SwiftData

struct CategoryManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \MerchantRule.lastUsedAt, order: .reverse) private var rules: [MerchantRule]
    @Query private var transactions: [Transaction]

    @State private var showAddSheet = false
    @State private var editingCategory: Category?
    @State private var showDeleteAlert = false
    @State private var pendingDelete: Category?

    private var learnedSummary: [(merchant: String, category: String, count: Int)] {
        var grouped: [String: (category: String, count: Int)] = [:]
        for item in transactions where !item.isDeleted && !item.merchant.isEmpty {
            let key = item.merchant
            var current = grouped[key] ?? (item.categoryName, 0)
            current.count += 1
            current.category = item.categoryName
            grouped[key] = current
        }
        return grouped
            .map { (merchant: $0.key, category: $0.value.category, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories) { category in
                        Button {
                            editingCategory = category
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: category.symbolName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(category.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(category.name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(category.scope.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                                if category.isSystem {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if !category.isSystem {
                                Button(role: .destructive) {
                                    pendingDelete = category
                                    showDeleteAlert = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        reorder(from: source, to: destination)
                    }
                } header: {
                    Text("分类")
                } footer: {
                    Text("系统分类不能删除，但可以改颜色和图标。自定义分类删除后，原有账单会归到「其他」。")
                }

                Section {
                    if rules.isEmpty {
                        Text("还没有学习记录。你每改一次账单的分类，这里就会多一条规则。")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(rules.prefix(30)) { rule in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.displayName.isEmpty ? rule.pattern : rule.displayName)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("命中 \(rule.hitCount) 次")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                Text(rule.categoryName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.brand)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    context_delete(rule)
                                } label: {
                                    Label("移除", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("商户分类规则（自动学习）")
                } footer: {
                    Text("例如你把「中石化」记成加油，以后遇到中石化就自动归到加油。")
                }

                if !learnedSummary.isEmpty {
                    Section("你的消费习惯") {
                        ForEach(Array(learnedSummary.enumerated()), id: \.offset) { _, item in
                            HStack {
                                Text(item.merchant)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(item.category) · \(item.count) 次")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("分类管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showAddSheet) {
                CategoryEditorView(category: nil)
            }
            .sheet(item: $editingCategory) { category in
                CategoryEditorView(category: category)
            }
            .alert("删除这个分类？", isPresented: $showDeleteAlert) {
                Button("删除", role: .destructive) {
                    if let pendingDelete { delete(pendingDelete) }
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("这个分类下的账单会被移到「其他」，账单本身不会丢。")
            }
        }
    }

    // MARK: - 动作

    private func reorder(from source: IndexSet, to destination: Int) {
        var ordered = categories
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() {
            category.sortIndex = index
        }
        try? modelContext.save()
    }

    private func delete(_ category: Category) {
        let fallback = categories.first { $0.name == "其他" }
        for item in transactions where item.categoryName == category.name {
            item.categoryName = fallback?.name ?? "其他"
            item.categoryID = fallback?.id
        }
        modelContext.delete(category)
        try? modelContext.save()
        pendingDelete = nil
        SnapshotWriter.refresh(in: modelContext)
        Haptics.warning()
    }

    private func context_delete(_ rule: MerchantRule) {
        modelContext.delete(rule)
        try? modelContext.save()
    }
}

// MARK: - 分类编辑

private struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    let category: Category?

    @State private var name = ""
    @State private var symbolName = "tag.fill"
    @State private var colorHex = "#34C759"
    @State private var scope: CategoryScope = .expense

    private let palette = ["#34C759", "#FF9F0A", "#FF6B6B", "#4C9AFF", "#8E7CFF",
                           "#FF5FA2", "#FFC53D", "#35C2A6", "#7E8CA0", "#FF8A3D"]

    private let symbolOptions = ["fork.knife", "bag.fill", "car.fill", "fuelpump.fill",
                                 "gamecontroller.fill", "popcorn.fill", "bolt.fill", "house.fill",
                                 "cross.case.fill", "book.fill", "airplane", "gift.fill",
                                 "briefcase.fill", "yensign.circle.fill", "tag.fill", "cup.and.saucer.fill",
                                 "pawprint.fill", "figure.run", "camera.fill", "heart.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如：宠物", text: $name)
                }

                Section("图标") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(symbolOptions, id: \.self) { symbol in
                            Button {
                                symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 16))
                                    .foregroundStyle(symbol == symbolName ? .white : Theme.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        symbol == symbolName ? (Color(hex: colorHex) ?? Theme.brand) : Theme.background,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("颜色") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 12)], spacing: 12) {
                        ForEach(palette, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? Theme.brand)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if hex == colorHex {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("适用范围") {
                    Picker("类型", selection: $scope) {
                        ForEach(CategoryScope.allCases, id: \.self) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let category, category.isSystem {
                    Section {
                        Text("系统分类不能删除，但可以修改名称、图标和颜色。")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .navigationTitle(category == nil ? "新建分类" : "编辑分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let category else { return }
                name = category.name
                symbolName = category.symbolName
                colorHex = category.colorHex
                scope = category.scope
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let category {
            let oldName = category.name
            category.name = trimmed
            category.symbolName = symbolName
            category.colorHex = colorHex
            category.scope = scope
            // 同步历史账单上的冗余分类名
            if oldName != trimmed {
                let all = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
                for item in all where item.categoryName == oldName {
                    item.categoryName = trimmed
                }
            }
        } else {
            let maxIndex = categories.map(\.sortIndex).max() ?? 0
            let newCategory = Category(
                name: trimmed,
                symbolName: symbolName,
                colorHex: colorHex,
                scope: scope,
                isSystem: false,
                sortIndex: maxIndex + 1
            )
            modelContext.insert(newCategory)
        }
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }
}
