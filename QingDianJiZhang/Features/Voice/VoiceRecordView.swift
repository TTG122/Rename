//
//  VoiceRecordView.swift
//  轻点记账
//
//  语音记账：「今天中午吃饭花了28元」→ 支出 28 元 · 吃饭 · 今天 12:00
//

import SwiftUI
import SwiftData

struct VoiceRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router

    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var recorder = VoiceRecorder()
    @State private var preview: ParsedReceipt?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 8)

                waveform

                Text(displayText)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 60)
                    .padding(.horizontal, 24)
                    .animation(.easeInOut, value: recorder.transcript)

                if let preview {
                    parsedPreview(preview)
                }

                Spacer()

                if let message = recorder.errorMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.expense)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                controls

                Text(recorder.isOnDevice ? "正在使用设备端识别，录音不会上传" : "设备不支持端侧识别时会使用系统在线识别")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 12)
            }
            .background(Theme.background)
            .navigationTitle("语音记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                _ = await recorder.requestAuthorization()
            }
            .onChange(of: recorder.transcript) { _, newValue in
                guard !newValue.isEmpty else { return }
                preview = VoiceCommandParser.parse(text: newValue)
            }
        }
    }

    private var displayText: String {
        if !recorder.transcript.isEmpty { return recorder.transcript }
        switch recorder.phase {
        case .recording: return "在听……"
        case .denied: return "需要麦克风和语音识别权限"
        case .unavailable(let message): return message
        default: return "试试说：今天中午吃饭花了28元"
        }
    }

    private var waveform: some View {
        ZStack {
            Circle()
                .fill(Theme.brandSoft)
                .frame(width: 150, height: 150)
                .scaleEffect(recorder.phase == .recording ? 1 + recorder.audioLevel * 0.28 : 1)
                .animation(.easeOut(duration: 0.12), value: recorder.audioLevel)

            Circle()
                .fill(Theme.brand)
                .frame(width: 96, height: 96)

            Image(systemName: recorder.phase == .recording ? "waveform" : "mic.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: recorder.phase == .recording)
        }
        .frame(height: 170)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if recorder.phase == .recording {
                Button {
                    recorder.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.expense))
            } else if preview != nil {
                Button {
                    save()
                } label: {
                    Label("确认记一笔", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    recorder.reset()
                    recorder.start()
                } label: {
                    Label("开始说话", systemImage: "mic.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 24)
    }

    private func parsedPreview(_ parsed: ParsedReceipt) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parsed.kind.sign)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(parsed.kind.tint)
                Text("¥\(parsed.amountYuanText)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(parsed.kind.tint)
            }

            HStack(spacing: 8) {
                label(parsed.kind.title)
                if !parsed.merchant.isEmpty {
                    label(parsed.merchant)
                }
                label(DateText.dayTitle(for: parsed.occurredAt) + " " + DateText.timeFormatter.string(from: parsed.occurredAt))
            }

            let classification = RuleBasedClassifier().classify(
                ClassificationInput(
                    merchant: parsed.merchant,
                    item: parsed.item,
                    rawText: parsed.rawText,
                    kind: parsed.kind,
                    learnedRules: CapturePipeline.learnedRules(in: modelContext),
                    availableCategories: categories.map(\.name)
                )
            )
            Text("推荐分类：\(classification.categoryName)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.brand)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.8)
        }
        .padding(.horizontal, 24)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.background, in: Capsule())
    }

    private func save() {
        guard let preview, preview.hasUsableAmount else {
            router.showToast(
                AppToast(title: "没听清金额", subtitle: "再说一次试试，例如「吃饭花了28元」", symbol: "mic.slash.fill", tint: .orange),
                autoDismissAfter: 2.5
            )
            return
        }

        let classification = RuleBasedClassifier().classify(
            ClassificationInput(
                merchant: preview.merchant,
                item: preview.item,
                rawText: preview.rawText,
                kind: preview.kind,
                learnedRules: CapturePipeline.learnedRules(in: modelContext),
                availableCategories: categories.map(\.name)
            )
        )

        var draft = TransactionDraft.from(
            parsed: preview,
            classification: classification,
            source: .voice,
            imageData: nil,
            imageHash: "",
            perceptualHash: "",
            categories: categories
        )
        draft.source = .voice

        let transaction = RecordService.save(draft: draft, in: modelContext, categories: categories)
        let id = transaction.id
        Haptics.success()

        router.dismissToast()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            AppRouter.shared.showSaved(transaction: transaction) {
                CapturePipeline.deleteByID(id, context: modelContext)
            }
        }
    }
}
