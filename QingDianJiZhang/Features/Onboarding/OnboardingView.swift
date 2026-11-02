//
//  OnboardingView.swift
//  简记
//
//  新用户引导：讲清楚「双击背面 → 2 秒记账」这件事，把权限和快捷指令一次配好。
//

import SwiftUI
import AVFoundation
import Speech
import Photos

struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppRouter.self) private var router

    @State private var page = 0
    @State private var showSetupGuide = false
    @State private var permissionsRequested = false

    private let pageCount = 4

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    howItWorksPage.tag(1)
                    privacyPage.tag(2)
                    permissionPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: page)

                footer
            }
        }
        .sheet(isPresented: $showSetupGuide) {
            SetupGuideView()
        }
    }

    // MARK: - 页脚

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.brand : Theme.separator)
                        .frame(width: index == page ? 18 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                }
            }

            HStack(spacing: 12) {
                if page > 0 {
                    Button("上一步") {
                        withAnimation { page -= 1 }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(width: 110)
                }

                Button(page == pageCount - 1 ? "开始记账" : "下一步") {
                    advance()
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if page < pageCount - 1 {
                Button("跳过") {
                    finish()
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }

    private func advance() {
        if page == pageCount - 1 {
            finish()
        } else {
            withAnimation { page += 1 }
        }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        router.showOnboarding = false
        Haptics.success()
    }

    // MARK: - 第 1 页

    private var welcomePage: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.brandSoft)
                    .frame(width: 168, height: 168)
                Circle()
                    .fill(Theme.brand.opacity(0.16))
                    .frame(width: 128, height: 128)
                VStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(Theme.brand)
                    Text("双击背面")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                }
            }

            VStack(spacing: 10) {
                Text("简记")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("付完钱，双击手机背面\n2 秒记完一笔")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(spacing: 10) {
                featureLine("不用打开 App，不打断你正在做的事")
                featureLine("自动识别金额、商户和消费分类")
                featureLine("所有账单只存在你的 iPhone 上")
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func featureLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.brand)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    // MARK: - 第 2 页

    private var howItWorksPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("它是怎么工作的")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 40)

                Text("整条链路都在 iOS 允许的范围内，没有任何越界读取。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)

                flowStep(index: "1", title: "你付完钱，停在支付成功页", detail: "微信、支付宝、银行、外卖、购物 App 都行")
                flowStep(index: "2", title: "双击 iPhone 背面", detail: "系统轻震一下，运行「简记」快捷指令")
                flowStep(index: "3", title: "本机识别截图文字", detail: "Apple Vision 在你的手机上提取金额和商户")
                flowStep(index: "4", title: "弹出分类面板", detail: "推荐分类已经选好，点一下或者直接确认")
                flowStep(index: "5", title: "完成，自动收起", detail: "2 秒内回到原来的页面，还能点撤销")

                VStack(alignment: .leading, spacing: 6) {
                    Text("如果识别不准？")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("面板里可以直接改金额、换分类、加备注。你每改一次，App 就记住一次——下次同一个商户会直接推荐你改过的分类。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, 20)
        }
    }

    private func flowStep(index: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(index)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Theme.brand, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - 第 3 页

    private var privacyPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.brand)
                    .padding(.top, 44)

                Text("你的账，只在你手机上")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("这不是一句口号，是技术实现方式。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)

                privacyItem(symbol: "iphone", title: "识别在本机完成", detail: "截图文字提取用 Apple Vision，分类用本机词典和本地模型，都不联网。")
                privacyItem(symbol: "icloud.slash", title: "默认不上传", detail: "iCloud 同步和云端 AI 都是默认关闭的，要用你自己去开。")
                privacyItem(symbol: "eye.slash", title: "不偷看其他 App", detail: "不读取微信支付宝的订单，不读剪贴板，不常驻后台监控。")
                privacyItem(symbol: "creditcard", title: "不存完整卡号", detail: "只保留后四位用于区分账户。")
                privacyItem(symbol: "square.and.arrow.up", title: "随时带走", detail: "设置里可以一键导出全部数据为 CSV，也可以一键永久删除。")

                Text("更完整的说明见「设置 → 隐私说明」。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, 20)
        }
    }

    private func privacyItem(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.brand)
                .frame(width: 28, height: 28)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: - 第 4 页

    private var permissionPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("最后两步")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 44)

                Text("配置好之后，你就可以完全不用打开这个 App 了。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "1.circle.fill")
                            .foregroundStyle(Theme.brand)
                        Text("开启需要的权限")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text("相册（读截图）、麦克风与语音识别（语音记账）。都可以在系统设置里随时关掉。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)

                    Button {
                        requestPermissions()
                    } label: {
                        Text(permissionsRequested ? "已请求，可在系统设置中修改" : "开启权限")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(permissionsRequested)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "2.circle.fill")
                            .foregroundStyle(Theme.brand)
                        Text("配置双击背面")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text("设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下 → 选「简记」。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)

                    Button {
                        showSetupGuide = true
                    } label: {
                        Text("查看图文教程")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("先不配也能用")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("首页的「记一笔」、语音记账、相册导入都可以随时用，双击背面只是最快的那个入口。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineSpacing(2)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 权限

    private func requestPermissions() {
        permissionsRequested = true

        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }

        SFSpeechRecognizer.requestAuthorization { _ in }

        AVAudioApplication.requestRecordPermission { _ in }
    }
}
