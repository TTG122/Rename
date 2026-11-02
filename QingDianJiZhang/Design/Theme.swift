//
//  Theme.swift
//  轻点记账
//
//  视觉系统：苹果原生语言 + 清新绿主色。
//  所有颜色都是语义色，自动适配深色模式。
//

import SwiftUI
import UIKit

enum Theme {
    // MARK: 主色
    /// 清新苹果绿
    static let brand = Color(light: "#34C759", dark: "#30D158")
    static let brandSoft = Color(light: "#E8F9ED", dark: "#12301D")

    // MARK: 收支
    static let income = Color(light: "#34C759", dark: "#30D158")
    /// 柔和橙红
    static let expense = Color(light: "#F26B4E", dark: "#FF8266")

    // MARK: 背景
    static let background = Color(light: "#F4F5F7", dark: "#000000")
    static let groupedBackground = Color(light: "#F4F5F7", dark: "#0B0B0C")
    static let card = Color(light: "#FFFFFF", dark: "#1C1C1E")
    static let cardElevated = Color(light: "#FFFFFF", dark: "#242426")

    // MARK: 文本
    static let textPrimary = Color(light: "#111214", dark: "#F5F5F7")
    static let textSecondary = Color(light: "#8A8F98", dark: "#9A9FA6")
    static let textTertiary = Color(light: "#B4B9C0", dark: "#6E7378")

    // MARK: 分隔与描边
    static let separator = Color(light: "#E9EBEF", dark: "#2C2C2E")
    static let stroke = Color(light: "#EDEFF2", dark: "#2C2C2E")

    // MARK: 尺寸
    enum Radius {
        static let card: CGFloat = 18
        static let panel: CGFloat = 28
        static let chip: CGFloat = 14
        static let field: CGFloat = 12
    }

    enum Spacing {
        static let page: CGFloat = 20
        static let section: CGFloat = 24
        static let cardInner: CGFloat = 16
    }
}

// MARK: - 颜色工具

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// 明暗双色
    init(light: String, dark: String) {
        let lightColor = Color(hex: light) ?? .gray
        let darkColor = Color(hex: dark) ?? .gray
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(darkColor) : UIColor(lightColor)
        })
    }
}

// MARK: - 常用修饰

struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    var padding: CGFloat = Theme.Spacing.cardInner

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func cardStyle(radius: CGFloat = Theme.Radius.card, padding: CGFloat = Theme.Spacing.cardInner) -> some View {
        modifier(CardBackground(radius: radius, padding: padding))
    }

    /// 页面级背景
    func pageBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}
