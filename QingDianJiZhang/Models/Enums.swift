//
//  Enums.swift
//  简记
//
//  全局枚举定义。所有 @Model 里以 Raw 字符串落库，避免 SwiftData 迁移时
//  对枚举 CaseIterable 支持不足导致的问题。
//

import Foundation
import SwiftUI

// MARK: - 收支类型

enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        }
    }

    var sign: String {
        switch self {
        case .expense: return "-"
        case .income: return "+"
        }
    }

    var tint: Color {
        switch self {
        case .expense: return Theme.expense
        case .income: return Theme.income
        }
    }
}

// MARK: - 数据来源

enum TransactionSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case backTap
    case manual
    case voice
    case receipt
    case share
    case screenshot
    case fileImport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backTap: return "双击背面"
        case .manual: return "手动记账"
        case .voice: return "语音记账"
        case .receipt: return "小票拍摄"
        case .share: return "系统分享"
        case .screenshot: return "截图导入"
        case .fileImport: return "账单导入"
        }
    }

    var symbolName: String {
        switch self {
        case .backTap: return "hand.tap"
        case .manual: return "square.and.pencil"
        case .voice: return "waveform"
        case .receipt: return "doc.text.viewfinder"
        case .share: return "square.and.arrow.down"
        case .screenshot: return "photo"
        case .fileImport: return "tray.and.arrow.down"
        }
    }
}

// MARK: - 记账模式

enum RecordMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 每一笔都弹窗确认
    case confirmEveryTime
    /// 置信度达标自动入账，只给成功提示 + 撤销
    case smartAuto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .confirmEveryTime: return "每笔确认"
        case .smartAuto: return "智能自动"
        }
    }

    var detail: String {
        switch self {
        case .confirmEveryTime: return "每笔账单都弹窗，点一下分类才入账"
        case .smartAuto: return "识别够准时直接入账，只显示结果和撤销"
        }
    }
}

// MARK: - 支付平台

enum PaymentPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case wechat
    case alipay
    case unionPay
    case applePay
    case bankCard
    case cash
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wechat: return "微信支付"
        case .alipay: return "支付宝"
        case .unionPay: return "云闪付"
        case .applePay: return "Apple Pay"
        case .bankCard: return "银行卡"
        case .cash: return "现金"
        case .other: return "其他"
        }
    }

    var symbolName: String {
        switch self {
        case .wechat: return "message.fill"
        case .alipay: return "a.circle.fill"
        case .unionPay: return "creditcard.fill"
        case .applePay: return "apple.logo"
        case .bankCard: return "building.columns.fill"
        case .cash: return "banknote.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}
