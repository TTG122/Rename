//
//  SetupGuideView.swift
//  轻点记账
//
//  双击背面 + 快捷指令的完整配置教程。这是整个产品的入口，必须讲得足够清楚。
//

import SwiftUI

struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    step1
                    step2
                    step3
                    step4
                    limits
                }
                .padding(Theme.Spacing.page)
            }
            .background(Theme.background)
            .navigationTitle("双击背面设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - 顶部

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                Text("一次设置，永久生效")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("配好之后，在任何 App 的支付成功页双击手机背面，就会弹出识别面板，点一下分类就记好了。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 18, padding: 16)
    }

    // MARK: - 步骤

    private var step1: some View {
        StepCard(index: 1, title: "创建一个快捷指令") {
            VStack(alignment: .leading, spacing: 8) {
                Text("打开「快捷指令」App → 点右上角 + → 新建一个快捷指令，命名为「轻点记账」。")
                Text("然后依次添加 3 个操作：")
                actionList([
                    ("1", "获取图像", "输入类型选「图像」，来源用「快捷指令输入」"),
                    ("2", "轻点记账", "在搜索框搜「轻点记账」，选「识别并记账」"),
                    ("3", "保存到相册（可选）", "想留一份截图备份就加这一步")
                ])
                Button {
                    openShortcuts()
                } label: {
                    Label("打开快捷指令 App", systemImage: "square.stack.3d.up.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.brand)
                .padding(.top, 4)
            }
        }
    }

    private var step2: some View {
        StepCard(index: 2, title: "打开「轻点背面」") {
            VStack(alignment: .leading, spacing: 8) {
                Text("设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下 → 选择「轻点记账」。")
                Text("这条路是系统级的，所以你在任何 App 里双击背面都能触发，不需要我们常驻后台。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                Button {
                    openAccessibilitySettings()
                } label: {
                    Label("打开设置", systemImage: "gearshape.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.brand)
            }
        }
    }

    private var step3: some View {
        StepCard(index: 3, title: "允许权限") {
            VStack(alignment: .leading, spacing: 6) {
                Text("第一次运行时，系统会问你要「相册」权限——用于读取你刚截的图，以及保存截图备份。")
                Text("语音记账需要「麦克风」和「语音识别」权限，可以在设置页里随时关闭。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var step4: some View {
        StepCard(index: 4, title: "试一次") {
            VStack(alignment: .leading, spacing: 8) {
                Text("随便打开一张支付截图，双击手机背面。你会感觉到一下轻震，然后弹出识别面板。")
                Text("如果没反应，回到第 2 步确认「轻点两下」确实选到了「轻点记账」。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - 说明

    private var limits: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("关于「自动读取」的实话")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("iOS 不允许第三方 App 在后台读取微信、支付宝里的订单。所以我们的做法是：")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text("· 优先让快捷指令把你当前屏幕的截图传进来，识别在本机完成")
            Text("· 拿不到截图时，可以用分享菜单把截图发到轻点记账，或者从相册批量导入")
            Text("· 也可以直接导入微信 / 支付宝导出的账单文件，一次补齐历史")
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textTertiary)
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 18, padding: 16)
    }

    // MARK: - 工具

    private func actionList(_ items: [(String, String, String)]) -> some View {
        VStack(spacing: 8) {
            ForEach(items, id: \.0) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.0)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Theme.brand, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.1)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(item.2)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func openShortcuts() {
        if let url = URL(string: "shortcuts://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func openAccessibilitySettings() {
        // 系统设置深链。部分 iOS 版本会忽略 path，此时打开设置首页也能找到入口。
        let candidates = [
            "App-prefs:root=ACCESSIBILITY&path=TOUCH",
            "App-prefs:root=ACCESSIBILITY",
            UIApplication.openSettingsURLString
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }
}

// MARK: - 步骤卡片

struct StepCard<Content: View>: View {
    let index: Int
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(index)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Theme.brand, in: Circle())
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            content()
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 18, padding: 16)
    }
}
