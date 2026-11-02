//
//  TransactionRow.swift
//  简记
//

import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction
    var category: Category?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category?.symbolName ?? "ellipsis.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    (category?.color ?? Theme.textTertiary),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(transaction.displaySubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(transaction.signedAmountText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(transaction.kind.tint)
                Text(DateText.listStamp(for: transaction.occurredAt))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 分组头

struct DaySectionHeader: View {
    let date: Date
    let expenseCents: Int
    let incomeCents: Int

    var body: some View {
        HStack {
            Text(DateText.dayTitle(for: date))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if expenseCents > 0 {
                Text("支 ¥\(MoneyFormatter.grouped(cents: expenseCents))")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            if incomeCents > 0 {
                Text("收 ¥\(MoneyFormatter.grouped(cents: incomeCents))")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.income)
            }
        }
        .padding(.vertical, 6)
    }
}
