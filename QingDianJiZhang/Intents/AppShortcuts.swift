//
//  AppShortcuts.swift
//  简记
//
//  系统「快捷指令」里的预设入口。用户装完 App 就能在快捷指令库看到这几条，
//  不需要自己从零搭。
//

import AppIntents

struct QingDianAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordFromImageIntent(),
            phrases: [
                "用\(.applicationName)记一笔",
                "让\(.applicationName)识别这张截图",
                "\(.applicationName)记账"
            ],
            shortTitle: "识别并记账",
            systemImageName: "hand.tap.fill"
        )

        AppShortcut(
            intent: QuickTextRecordIntent(),
            phrases: [
                "用\(.applicationName)说一句记账",
                "\(.applicationName)语音记账"
            ],
            shortTitle: "说一句就记账",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: OpenQuickRecordIntent(),
            phrases: [
                "打开\(.applicationName)"
            ],
            shortTitle: "打开简记",
            systemImageName: "house.fill"
        )
    }
}
