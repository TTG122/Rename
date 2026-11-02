//
//  BudgetEditorView.swift
//  简记
//

import SwiftUI
import SwiftData

struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var budgets: [Budget]
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var totalText = ""
    @State private var categoryBudgets: [UUID: String] = [:]

    private var totalBudget: Budget? {
        budgets.first { $0.isTotalBudget && $0.monthKey.isEmpty }
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.scope != .income }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("¥")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.brand)
                        TextField("3000", text: $totalText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("每月总预算")
                } footer: {
                    Text("留空表示不设置预算。预算只在你本机保存，不会上传。")
                }

                Section {
                    ForEach(expenseCategories) { category in
                        HStack(spacing: 10) {
                            Image(systemName: category.symbolName)
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(category.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(category.name)
                                .font(.system(size: 14))
                            Spacer()
                            TextField("不限", text: binding(for: category))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 14))
                                .frame(width: 90)
                        }
                    }
                } header: {
                    Text("分类预算（可选）")
                } footer: {
                    Text("分类预算用来做单项提醒，比如把游戏控制在 500 元。")
                }
            }
            .navigationTitle("预算管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func binding(for category: Category) -> Binding<String> {
        Binding(
            get: { categoryBudgets[category.id] ?? "" },
            set: { categoryBudgets[category.id] = $0 }
        )
    }

    private func load() {
        if let totalBudget {
            totalText = MoneyFormatter.string(cents: totalBudget.amountCents)
        }
        for category in expenseCategories {
            if let budget = budgets.first(where: { $0.categoryID == category.id && $0.monthKey.isEmpty }) {
                categoryBudgets[category.id] = MoneyFormatter.string(cents: budget.amountCents)
            }
        }
    }

    private func save() {
        // 总预算
        if let cents = MoneyFormatter.cents(fromYuanText: totalText), cents > 0 {
            if let totalBudget {
                totalBudget.amountCents = cents
                totalBudget.updatedAt = .now
            } else {
                modelContext.insert(Budget(monthKey: "", amountCents: cents))
            }
        } else if let totalBudget {
            modelContext.delete(totalBudget)
        }

        // 分类预算
        for category in expenseCategories {
            let text = categoryBudgets[category.id] ?? ""
            let existing = budgets.first { $0.categoryID == category.id && $0.monthKey.isEmpty }
            if let cents = MoneyFormatter.cents(fromYuanText: text), cents > 0 {
                if let existing {
                    existing.amountCents = cents
                    existing.updatedAt = .now
                } else {
                    modelContext.insert(
                        Budget(monthKey: "", amountCents: cents, categoryID: category.id, categoryName: category.name)
                    )
                }
            } else if let existing {
                modelContext.delete(existing)
            }
        }

        try? modelContext.save()
        SnapshotWriter.refresh(in: modelContext)
        Haptics.success()
        dismiss()
    }
}
