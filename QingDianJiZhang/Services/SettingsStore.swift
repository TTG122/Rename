//
//  SettingsStore.swift
//  简记
//
//  用户设置。全部落 UserDefaults，不上云。
//
//  实现说明：这里刻意不使用 didSet 来写盘。
//  @Observable 宏会把存储属性改写成带 getter/setter 的计算属性，
//  和 didSet 组合容易在宏展开时打架。所以改成「UserDefaults 是唯一真相 +
//  revision 计数驱动观察」：每次写入 bump 一次 revision，
//  读取时先 registerRead() 建立依赖，视图就会正确刷新。
//

import Foundation
import Observation
import SwiftUI

@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    /// 观察驱动用。任何设置的写入都会让它 +1，读取设置时建立依赖。
    private(set) var revision: Int = 0

    private enum Key {
        static let recordMode = "settings.recordMode"
        static let autoThreshold = "settings.autoThreshold"
        static let defaultAccount = "settings.defaultAccount"
        static let faceIDEnabled = "settings.faceIDEnabled"
        static let onboarding = "settings.onboarding"
        static let iCloudSync = "settings.iCloudSync"
        static let cloudAI = "settings.cloudAI"
        static let monthlyReminder = "settings.monthlyReminder"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 测试用独立实例
    static func makeEphemeral() -> SettingsStore {
        let suiteName = "settings.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return SettingsStore(defaults: defaults)
    }

    // MARK: - 观察辅助

    private func registerRead() {
        // 触碰一次可观察属性，让 SwiftUI 建立依赖
        _ = revision
    }

    private func bump() {
        revision &+= 1
    }

    // MARK: - 记账模式

    var recordMode: RecordMode {
        get {
            registerRead()
            return RecordMode(rawValue: defaults.string(forKey: Key.recordMode) ?? "") ?? .confirmEveryTime
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.recordMode)
            bump()
        }
    }

    /// 智能自动模式下的置信度阈值 0.5...0.99
    var autoThreshold: Double {
        get {
            registerRead()
            let stored = defaults.double(forKey: Key.autoThreshold)
            return stored > 0 ? min(max(stored, 0.5), 0.99) : 0.82
        }
        set {
            defaults.set(min(max(newValue, 0.5), 0.99), forKey: Key.autoThreshold)
            bump()
        }
    }

    var thresholdPercentText: String {
        "\(Int((autoThreshold * 100).rounded()))%"
    }

    // MARK: - 账户

    var defaultAccount: String {
        get {
            registerRead()
            let value = defaults.string(forKey: Key.defaultAccount) ?? ""
            return value.isEmpty ? "默认账户" : value
        }
        set {
            defaults.set(newValue, forKey: Key.defaultAccount)
            bump()
        }
    }

    // MARK: - 安全

    var faceIDEnabled: Bool {
        get {
            registerRead()
            return defaults.bool(forKey: Key.faceIDEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.faceIDEnabled)
            bump()
        }
    }

    var hasCompletedOnboarding: Bool {
        get {
            registerRead()
            return defaults.bool(forKey: Key.onboarding)
        }
        set {
            defaults.set(newValue, forKey: Key.onboarding)
            bump()
        }
    }

    // MARK: - 同步与云

    var iCloudSyncEnabled: Bool {
        get {
            registerRead()
            return defaults.bool(forKey: Key.iCloudSync)
        }
        set {
            defaults.set(newValue, forKey: Key.iCloudSync)
            bump()
        }
    }

    /// 云端 AI 默认关闭，必须用户主动开启（隐私承诺）
    var cloudAIEnabled: Bool {
        get {
            registerRead()
            return defaults.bool(forKey: Key.cloudAI)
        }
        set {
            defaults.set(newValue, forKey: Key.cloudAI)
            bump()
        }
    }

    // MARK: - 提醒

    var monthlyReminderEnabled: Bool {
        get {
            registerRead()
            return defaults.bool(forKey: Key.monthlyReminder)
        }
        set {
            defaults.set(newValue, forKey: Key.monthlyReminder)
            bump()
        }
    }
}
