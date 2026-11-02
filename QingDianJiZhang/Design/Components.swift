//
//  Components.swift
//  简记
//
//  设计系统里的可复用零件。统一圆角、字重、留白，保证全 App 视觉一致。
//

import SwiftUI

// MARK: - 金额

struct MoneyText: View {
    let cents: Int
    var kind: TransactionKind = .expense
    var size: CGFloat = 34
    var showSign: Bool = false
    var useGrouping: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("¥")
                .font(.system(size: size * 0.52, weight: .semibold, design: .rounded))
                .foregroundStyle(kind.tint.opacity(0.75))
            Text((showSign ? kind.sign : "") + displayNumber)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(kind.tint)
                .contentTransition(.numericText())
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title) \(displayNumber) 元")
    }

    private var displayNumber: String {
        useGrouping ? MoneyFormatter.grouped(cents: cents) : MoneyFormatter.string(cents: cents)
    }
}

// MARK: - 分类胶囊

struct CategoryChip: View {
    let name: String
    let symbolName: String
    let color: Color
    var isSelected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                Text(name)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    Capsule().fill(color)
                } else {
                    Capsule().fill(Theme.card)
                }
            }
            .overlay {
                Capsule().strokeBorder(isSelected ? color : Theme.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: - 章节标题

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.brand)
            }
        }
    }
}

// MARK: - 数据块

struct StatTile: View {
    let title: String
    let value: String
    var caption: String?
    var tint: Color = Theme.textPrimary
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.8))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 进度条

struct BudgetProgressBar: View {
    let progress: Double
    var tint: Color = Theme.brand
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.separator)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.85), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(geometry.size.width, geometry.size.width * progress)))
            }
        }
        .frame(height: height)
        .accessibilityLabel("预算使用进度 \(Int(progress * 100))%")
    }
}

// MARK: - 主按钮

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.brand
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isEnabled ? tint : Theme.textTertiary)
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.brand)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 设置行

struct SettingsRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var tint: Color = Theme.brand
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - 轻提示条

struct ToastView: View {
    let toast: AppToast
    var onUndo: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(toast.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !toast.subtitle.isEmpty {
                    Text(toast.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer(minLength: 8)

            if toast.undo != nil {
                Button("撤销") {
                    Haptics.impact(.light)
                    onUndo()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.brand)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 16)
        .onTapGesture(perform: onDismiss)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
