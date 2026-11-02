//
//  CaptureConfirmView.swift
//  轻点记账
//
//  识别确认面板 —— 全 App 出现频率最高的界面。
//
//  设计目标：
//  · 一眼看到金额，第二眼看到商户，第三眼就能点到分类
//  · 点一个分类 = 完成记账（不需要再点「保存」）
//  · 半屏、毛玻璃、大圆角，视觉上贴近系统弹窗
//  · 单手可达：分类在下方三分之一区域
//

import SwiftUI
import SwiftData

struct CaptureConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query private var transactions: [Transaction]

    @State private var draft: TransactionDraft
    @State private var duplicate: DuplicateVerdict = .unique
    @State private var showAmountEditor = false
    @State private var showNoteEditor = false
    @State private var showDetail = false
    @State private var askDuplicate = false
    @State private var didEvaluate = false
    @State private var isSaving = false

    init(draft: TransactionDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                amountBlock

                if !draft.kindIsCertain {
                    kindPicker
                }

                if case .suspected(_, _, _, _, let reason) = duplicate {
                    duplicateBanner(reason: reason)
                }

                infoBlock
                categorySection

                Text("点一下分类就记好了，不会打断你现在用的 App")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(.ultraThinMaterial)
        .presentationDetents([.height(560), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.ultraThinMaterial)
        .task {
            guard !didEvaluate else { return }
            didEvaluate = true
            duplicate = CapturePipeline.checkDuplicate(draft, in: modelContext)
        }
        .sheet(isPresented: $showAmountEditor) {
            AmountEditView(cents: $draft.amountCents, kind: draft.kind)
                .presentationDetents([.height(360)])
        }
        .sheet(isPresented: $showNoteEditor) {
            NoteEditView(note: $draft.note)
                .presentationDetents([.height(300)])
        }
        .alert("这笔账单可能已经记录", isPresented: $askDuplicate) {
            Button("仍然记录") { commitSave(categoryName: draft.categoryName) }
            Button("取消", role: .cancel) { router.dismissConfirm() }
        } message: {
            if case .suspected(_, let title, let amount, _, let reason) = duplicate {
                Text("\(title) \(amount)\n\(reason)。要再记一笔吗？")
            } else {
                Text("检测到相似账单。")
            }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.brand)
            Text("轻点记账 · 识别结果")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                router.dismissConfirm()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 金额

    private var amountBlock: some View {
        VStack(spacing: 6) {
            Text(draft.kind == .expense ? "识别到一笔支出" : "识别到一笔收入")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Button {
                Haptics.selection()
                showAmountEditor = true
            } label: {
                MoneyText(
                    cents: draft.amountCents,
                    kind: draft.kind,
                    size: 46,
                    useGrouping: false
                )
                .overlay(alignment: .trailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textTertiary)
                        .offset(x: 22)
                }
            }
            .buttonStyle(.plain)

            if draft.amountCents == 0 {
                Text("没识别到金额，点上方数字手动填写")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.expense)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - 收支选择

    private var kindPicker: some View {
        HStack(spacing: 10) {
            ForEach(TransactionKind.allCases) { kind in
                Button {
                    Haptics.selection()
                    draft.kind = kind
                    // 切换方向后重新推荐分类
                    reclassify(for: kind)
                } label: {
                    Text(kind.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(draft.kind == kind ? .white : Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(draft.kind == kind ? kind.tint : Theme.card)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.stroke, lineWidth: draft.kind == kind ? 0 : 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .top) {
            Text("这是收入还是支出？")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .offset(y: -18)
        }
        .padding(.top, 14)
    }

    // MARK: - 重复提示

    private func duplicateBanner(reason: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("这笔账单可能已经记录")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 信息

    private var infoBlock: some View {
        VStack(spacing: 0) {
            if !draft.merchant.isEmpty {
                infoRow(symbol: "storefront", title: "商户", value: draft.merchant)
            }
            if !draft.item.isEmpty {
                infoRow(symbol: "bag", title: "内容", value: draft.item)
            }
            infoRow(symbol: "clock", title: "时间", value: DateText.fullFormatter.string(from: draft.occurredAt))
            if draft.platform != .other {
                infoRow(symbol: draft.platform.symbolName, title: "支付", value: draft.platform.title + (draft.account.isEmpty ? "" : " · \(draft.account)"))
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDetail.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("识别详情与备注")
                    Spacer()
                    Image(systemName: showDetail ? "chevron.up" : "chevron.down")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if showDetail {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("识别置信度 \(Int(draft.confidence * 100))%")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button(draft.note.isEmpty ? "添加备注" : "编辑备注") {
                            showNoteEditor = true
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.brand)
                    }
                    if !draft.classificationReason.isEmpty {
                        Text("分类依据：\(draft.classificationReason)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if !draft.note.isEmpty {
                        Text("备注：\(draft.note)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    ForEach(Array(draft.parserNotes.enumerated()), id: \.offset) { _, note in
                        Text("· \(note)")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.8)
        }
    }

    private func infoRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 9)
    }

    // MARK: - 分类

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("推荐分类：\(draft.categoryName)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if draft.confidence >= 0.7 {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.brand)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
                ForEach(visibleCategories, id: \.id) { category in
                    CategoryChip(
                        name: category.name,
                        symbolName: category.symbolName,
                        color: category.color,
                        isSelected: category.name == draft.categoryName
                    ) {
                        select(category)
                    }
                }
            }
        }
    }

    private var visibleCategories: [Category] {
        let filtered = categories
            .filter { !$0.isArchived && $0.isAvailable(for: draft.kind) }
            .sorted { $0.sortIndex < $1.sortIndex }
        return filtered.isEmpty ? categories : filtered
    }

    // MARK: - 动作

    private func select(_ category: Category) {
        draft.categoryName = category.name
        draft.categoryID = category.id
        Haptics.selection()

        if duplicate.isSuspected {
            askDuplicate = true
        } else {
            commitSave(categoryName: category.name)
        }
    }

    private func reclassify(for kind: TransactionKind) {
        let rules = CapturePipeline.learnedRules(in: modelContext)
        let result = RuleBasedClassifier().classify(
            ClassificationInput(
                merchant: draft.merchant,
                item: draft.item,
                rawText: draft.rawText,
                kind: kind,
                learnedRules: rules,
                availableCategories: CapturePipeline.availableNames(categories, kind: kind)
            )
        )
        draft.categoryName = result.categoryName
        draft.categoryID = SeedData.category(named: result.categoryName, in: categories)?.id
        draft.classificationReason = result.reason
    }

    private func commitSave(categoryName: String) {
        guard !isSaving, draft.amountCents > 0 else {
            showAmountEditor = true
            return
        }
        isSaving = true
        draft.categoryName = categoryName
        draft.categoryID = SeedData.category(named: categoryName, in: categories)?.id

        let transaction = RecordService.save(draft: draft, in: modelContext, categories: categories)
        let id = transaction.id

        Haptics.success()
        // 清空 pendingDraft 会让 sheet 自动收起，回到原来的支付页面
        AppRouter.shared.pendingDraft = nil
        AppRouter.shared.showSaved(transaction: transaction) {
            CapturePipeline.deleteByID(id, context: modelContext)
        }
    }
}

// MARK: - 金额编辑

private struct AmountEditView: View {
    @Binding var cents: Int
    var kind: TransactionKind
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("0.00", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .padding(.top, 24)

                HStack(spacing: 10) {
                    ForEach([10_00, 20_00, 50_00, 100_00], id: \.self) { preset in
                        Button("¥\(MoneyFormatter.string(cents: preset))") {
                            cents = preset
                            text = MoneyFormatter.string(cents: preset)
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.background, in: Capsule())
                    }
                }

                Spacer()

                Button("确定") {
                    if let value = MoneyFormatter.cents(fromYuanText: text), value > 0 {
                        cents = value
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(tint: kind.tint))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background(Theme.background)
            .navigationTitle("修改金额")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                text = cents > 0 ? MoneyFormatter.string(cents: cents) : ""
                focused = true
            }
        }
    }
}

// MARK: - 备注编辑

private struct NoteEditView: View {
    @Binding var note: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("例如：和同事聚餐", text: $text, axis: .vertical)
                    .lineLimit(3...5)
                    .focused($focused)
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("备注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        note = text
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                text = note
                focused = true
            }
        }
    }
}
