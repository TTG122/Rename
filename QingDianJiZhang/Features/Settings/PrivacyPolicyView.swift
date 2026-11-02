//
//  PrivacyPolicyView.swift
//  轻点记账
//
//  隐私说明（App Store 审核也会看这一页）。
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(String, String)] = [
        ("我们收集什么",
         "只收集你自己记的账单：金额、商户、分类、时间、备注，以及你导入的截图在识别时产生的文字。这些数据存放在你 iPhone 上的本地数据库（SwiftData）里。"),

        ("我们不收集什么",
         "我们不上传你的支付截图，不读取微信、支付宝、银行的账号密码，不保存银行卡完整卡号（只保留后四位用于区分账户），不读取剪贴板，不在后台监控你打开了哪些 App。"),

        ("识别在哪里完成",
         "金额、商户、时间的文字识别使用 Apple Vision 框架，在你的 iPhone 上完成。分类使用本机的规则词典，必要时叠加一个本机 Core ML 小模型，同样不联网。"),

        ("什么时候会联网",
         "只有两件事会联网：① iCloud 同步（需要你在设置里主动开启，并已登录 iCloud）；② 云端 AI 分析（默认关闭，开启后只上传脱敏后的月度统计，不含商户名和订单号）。这两项都可以随时关闭。"),

        ("关于「自动记账」的边界",
         "iOS 不允许第三方 App 在后台读取其他 App 的界面。我们的做法是通过「快捷指令 + 轻点背面」拿到你主动触发的截图，或者通过分享菜单、相册导入。我们不会、也无法在你不知情的时候读取其他 App 的内容。"),

        ("数据保存多久",
         "只要你没删，就一直存在你的手机上。你可以在设置 → 删除全部数据里一次性清空，也可以在账单列表里逐条删除。删除后无法恢复且我们服务器上没有任何副本（因为本来就没有）。"),

        ("导出与迁移",
         "设置 → 导出全部数据会生成一份 CSV，包含所有账单字段。你可以随时把数据带到别的工具里。"),

        ("第三方 SDK",
         "本 App 不集成任何第三方分析、广告或统计 SDK。App 内所有数字都由你的本地数据实时计算得出。"),

        ("儿童隐私",
         "本 App 不面向 13 岁以下儿童，也不会有意收集儿童信息。"),

        ("联系我们",
         "对隐私有任何疑问，可以通过 App Store 页面的开发者联系方式与我们联系。")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.brand)
                        Text("轻点记账的隐私原则")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("你的账，只在你自己的手机上。")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.bottom, 4)

                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.0)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(section.1)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle(radius: 16, padding: 14)
                    }

                    Text("最后更新：2026 年 11 月")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(Theme.Spacing.page)
            }
            .background(Theme.background)
            .navigationTitle("隐私说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
