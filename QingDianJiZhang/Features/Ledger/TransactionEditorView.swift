//
//  TransactionEditorView.swift
//  简记
//
//  手动记账 / 编辑账单。同一个界面支持新建与修改，避免两套代码走偏。
//

import SwiftUI
import SwiftData

struct TransactionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router

    @Query(sort: \Category.sortIndex) private var categories: [Category]

    private let editing: Transaction?

    @State private var kind: TransactionKind
    @State private var amountText: String
    @State private var merchant: String
    @State private var item: String
    @State private var note: String
    @State private var categoryName: String
    @State private var occurredAt: Date
    @State private var platform: PaymentPlatform
    @State private var account: String
    @State private var orderNumber: String
    @State private var showAdvanced = false
    @State private var showDatePicker = false
    @State private var showDeleteAlert = false

    // MARK: - 初始化

    init(mode: QuickEntryMode) {
        self.editing = nil
        _kind = State(initialValue: mode.kind)
        _amountText = State(initialValue: "")
        _merchant = State(initialValue: "")
        _item = State(initialValue: "")
        _note = State(initialValue: "")
        _categoryName = State(initialValue: mode.kind == .income ? "工资收入" : "吃饭")
        _occurredAt = State(initialValue: .now)
        _platform = State(initialValue: .wechat)
        _account = State(initialValue: SettingsStore.shared.defaultAccount)
        _orderNumber = State(initialValue: "")
    }

    init(transaction: Transaction) {
        self.editing = transaction
        _kind = State(initialValue: transaction.kind)
        _amountText = State(initialValue: MoneyFormatter.string(cents: transaction.amountCents))
        _merchant = State(initialValue: transaction.merchant)
        _item = State(initialValue: transaction.item)
        _note = State(initialValue: transaction.note)
        _categoryName = State(initialValue: transaction.categoryName)
        _occurredAt = State(initialValue: transaction.occurredAt)
        _platform = State(initialValue: transaction.platform)
        _account = State(initialValue: transaction.account)
        _orderNumber = State(initialValue: transaction.orderNumber)
        _showAdvanced = State(initialValue: !transaction.orderNumber.isEmpty)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    kindPicker
                    amountField
                    categoryGrid
                    detailFields
                    advancedFields

                    if editing != nil {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Text("删除这笔账单")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(Theme.expense.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(Theme.Spacing.page)
            }
            .background(Theme.background)
            .navigationTitle(editing == nil ? "记一笔" : "编辑账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
            .alert("确认删除这笔账单？", isPresented: $showDeleteAlert) {
                Button("删除", role: .destructive) {
                    if let editing {
                        RecordService.delete(editing, in: modelContext)
                        dismiss()
                    }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 子视图

    private var kindPicker: some View {
        HStack(spacing: 0) {
            ForEach(TransactionKind.allCases) { value in
                Button {
                    Haptics.selection()
                    kind = value
                    if !availableCategories.contains(where: { $0.name == categoryName }) {
                        categoryName = availableCategories.first?.name ?? "其他"
                    }
                } label: {
                    Text(value.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(kind == value ? .white : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if kind == value {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(value.tint)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.8)
        }
    }

    private var amountField: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(kind.tint.opacity(0.7))
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(kind.tint)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.8)
        }
    }

    private var availableCategories: [Category] {
        let filtered = categories.filter { !$0.isArchived && $0.isAvailable(for: kind) }
        return filtered.isEmpty ? categories : filtered
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分类")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                ForEach(availableCategories) { category in
                    CategoryChip(
                        name: category.name,
                        symbolName: category.symbolName,
                        color: category.color,
                        isSelected: category.name == categoryName
                    ) {
                        categoryName = category.name
                        Haptics.selection()
                    }
                }
            }
        }
    }

    private var detailFields: some View {
        VStack(spacing: 0) {
            fieldRow(title: "商户") {
                TextField("例如：星巴克", text: $merchant)
                    .multilineTextAlignment(.trailing)
            }
            Divider()
            fieldRow(title: "内容") {
                TextField("例如：拿铁大杯", text: $item)
                    .multilineTextAlignment(.trailing)
            }
            Divider()
            fieldRow(title: "时间") {
                Button {
                    showDatePicker.toggle()
                } label: {
                    Text(DateText.fullFormatter.string(from: occurredAt))
                        .foregroundStyle(Theme.brand)
                }
            }
            if showDatePicker {
                DatePicker("", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.vertical, 8)
            }
            Divider()
            fieldRow(title: "支付方式") {
                Picker("", selection: $platform) {
                    ForEach(PaymentPlatform.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .labelsHidden()
                .tint(Theme.brand)
            }
            Divider()
            fieldRow(title: "备注") {
                TextField("可不填", text: $note)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.8)
        }
    }

    private var advancedFields: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                HStack {
                    Text("更多信息")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if showAdvanced {
                Divider()
                fieldRow(title: "支付账户") {
                    TextField("例如：招商银行(1234)", text: $account)
                        .multilineTextAlignment(.trailing)
                }
                Divider()
                fieldRow(title: "订单号") {
                    TextField("用于查重", text: $orderNumber)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                }
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.8)
        }
    }

    private func fieldRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 68, alignment: .leading)
            content()
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(minHeight: 46)
    }

    // MARK: - 保存

    private var isValid: Bool {
        (MoneyFormatter.cents(fromYuanText: amountText) ?? 0) > 0
    }

    private func save() {
        guard let cents = MoneyFormatter.cents(fromYuanText: amountText), cents > 0 else { return }

        var draft = TransactionDraft()
        draft.kind = kind
        draft.amountCents = cents
        draft.merchant = merchant
        draft.item = item
        draft.note = note
        draft.categoryName = categoryName
        draft.categoryID = SeedData.category(named: categoryName, in: categories)?.id
        draft.occurredAt = occurredAt
        draft.platform = platform
        draft.account = account
        draft.orderNumber = orderNumber
        draft.source = editing?.source ?? .manual
        draft.confidence = 1.0
        draft.kindIsCertain = true

        if let editing {
            RecordService.update(editing, with: draft, in: modelContext)
            Haptics.success()
        } else {
            let transaction = RecordService.save(draft: draft, in: modelContext, categories: categories)
            let id = transaction.id
            AppRouter.shared.showSaved(transaction: transaction) {
                CapturePipeline.deleteByID(id, context: modelContext)
            }
        }
        dismiss()
    }
}
