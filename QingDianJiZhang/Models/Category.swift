//
//  Category.swift
//  简记
//

import Foundation
import SwiftData
import SwiftUI

/// 分类适用范围
enum CategoryScope: String, Codable, CaseIterable, Sendable {
    case expense
    case income
    case both

    var title: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        case .both: return "通用"
        }
    }
}

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    /// SF Symbols 名称
    var symbolName: String = "tag.fill"
    /// 16 进制颜色，例如 "#FF9F0A"
    var colorHex: String = "#34C759"
    var scopeRaw: String = "expense"
    /// 系统内置分类不可删除，只能排序 / 改颜色
    var isSystem: Bool = false
    var sortIndex: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String,
        colorHex: String,
        scope: CategoryScope = .expense,
        isSystem: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.scopeRaw = scope.rawValue
        self.isSystem = isSystem
        self.sortIndex = sortIndex
        self.isArchived = false
        self.createdAt = .now
    }
}

extension Category {
    var scope: CategoryScope {
        get { CategoryScope(rawValue: scopeRaw) ?? .expense }
        set { scopeRaw = newValue.rawValue }
    }

    var color: Color { Color(hex: colorHex) ?? Theme.expense }

    /// 适配收支方向的分类是否可用
    func isAvailable(for kind: TransactionKind) -> Bool {
        switch scope {
        case .both: return true
        case .expense: return kind == .expense
        case .income: return kind == .income
        }
    }
}

// MARK: - 系统内置分类

enum SystemCategories {
    struct Definition {
        let name: String
        let symbol: String
        let color: String
        let scope: CategoryScope
    }

    /// 顺序即确认面板里的展示顺序（常用在前）
    static let all: [Definition] = [
        Definition(name: "吃饭", symbol: "fork.knife", color: "#FF9F0A", scope: .expense),
        Definition(name: "购物", symbol: "bag.fill", color: "#FF6B6B", scope: .expense),
        Definition(name: "交通", symbol: "car.fill", color: "#4C9AFF", scope: .expense),
        Definition(name: "加油", symbol: "fuelpump.fill", color: "#FF8A3D", scope: .expense),
        Definition(name: "游戏", symbol: "gamecontroller.fill", color: "#8E7CFF", scope: .expense),
        Definition(name: "娱乐", symbol: "popcorn.fill", color: "#FF5FA2", scope: .expense),
        Definition(name: "水电", symbol: "bolt.fill", color: "#FFC53D", scope: .expense),
        Definition(name: "房租", symbol: "house.fill", color: "#6D8FA8", scope: .expense),
        Definition(name: "医疗", symbol: "cross.case.fill", color: "#35C2A6", scope: .expense),
        Definition(name: "教育", symbol: "book.fill", color: "#5E8BFF", scope: .expense),
        Definition(name: "旅游", symbol: "airplane", color: "#3FC8E4", scope: .expense),
        Definition(name: "人情", symbol: "gift.fill", color: "#FF7A9A", scope: .expense),
        Definition(name: "工作支出", symbol: "briefcase.fill", color: "#7E8CA0", scope: .expense),
        Definition(name: "工资收入", symbol: "yensign.circle.fill", color: "#34C759", scope: .income),
        Definition(name: "其他", symbol: "ellipsis.circle.fill", color: "#9AA0A6", scope: .both)
    ]

    static var defaultExpenseNames: [String] {
        all.filter { $0.scope != .income }.map(\.name)
    }
}
