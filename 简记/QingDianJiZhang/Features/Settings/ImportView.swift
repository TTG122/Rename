//
//  ImportView.swift
//  轻点记账
//
//  账单导入：文件（CSV / xlsx）、相册批量截图。
//  导入前会逐条查重，疑似重复的默认跳过。
//

import SwiftUI
import SwiftData
import UIKit

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router

    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query private var transactions: [Transaction]

    @State private var isWorking = false
    @State private var statusText = ""
    @State private var result: ImportService.Result?
    @State private var stagedDrafts: [TransactionDraft] = []
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    entryCard

                    if isWorking {
                        workingCard
                    }

                    if let result {
                        summaryCard(result)
                    }

                    if !stagedDrafts.isEmpty {
                        previewCard
                        Button {
                            commit()
                        } label: {
                            Text("导入 \(stagedDrafts.count) 笔账单")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    notesCard
                }
                .padding(Theme.Spacing.page)
            }
            .background(Theme.background)
            .navigationTitle("导入账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker { url in
                    handleFile(url)
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoImportPicker { images in
                    handleImages(images)
                }
            }
            .alert("导入失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 入口

    private var entryCard: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.selection()
                showFilePicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("从文件导入")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("微信 / 支付宝 / 银行导出的 CSV、Excel")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                Haptics.selection()
                showPhotoPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("批量导入截图")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("一次最多选 10 张支付截图")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .cardStyle(radius: 18, padding: 16)
    }

    private var workingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(statusText)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .cardStyle(radius: 16, padding: 14)
    }

    // MARK: - 结果

    private func summaryCard(_ result: ImportService.Result) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(result.detectedFormat)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                Spacer()
                Text("\(result.drafts.count) 笔")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }

            if result.skippedRows > 0 {
                Text("跳过 \(result.skippedRows) 行（金额为空或交易关闭）")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            if result.duplicateInFile > 0 {
                Text("文件内部重复 \(result.duplicateInFile) 行，已自动合并")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(result.warnings, id: \.self) { warning in
                Text("· \(warning)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.expense)
            }
        }
        .cardStyle(radius: 16, padding: 14)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("导入预览（前 8 笔）")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            ForEach(stagedDrafts.prefix(8)) { draft in
                HStack(spacing: 10) {
                    Text(draft.kind.sign)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(draft.kind.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(draft.merchant.isEmpty ? draft.item : draft.merchant)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text("\(DateText.dayTitle(for: draft.occurredAt)) · \(draft.categoryName)")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Text("¥\(draft.amountText)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.vertical, 3)
            }
        }
        .cardStyle(radius: 16, padding: 14)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("导入说明")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("· 微信：我 → 服务 → 钱包 → 账单 → 常见问题 → 下载账单 → 用于个人对账，解压后选 CSV")
            Text("· 支付宝：我的 → 账单 → 右上角 → 开具交易流水证明 → 导出 CSV")
            Text("· 文件全程在本机解析，不会上传到任何服务器")
            Text("· 导入时会自动按「订单号 / 金额 + 商户 + 时间」查重")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 16, padding: 14)
    }

    // MARK: - 处理

    private func handleFile(_ url: URL) {
        isWorking = true
        statusText = "正在解析文件…"
        result = nil
        stagedDrafts = []

        // 解析在 MainActor 上完成：需要读取 SwiftData 里的分类对象，
        // 这些对象不能跨线程访问。几千行的 CSV 解析耗时在几十毫秒量级。
        Task {
            do {
                let parsed = try ImportService.drafts(fromFileAt: url, categories: categories)
                result = parsed
                stagedDrafts = parsed.drafts
                isWorking = false
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    private func handleImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        isWorking = true
        statusText = "正在识别 \(images.count) 张截图…"
        stagedDrafts = []

        Task {
            var drafts: [TransactionDraft] = []
            for image in images {
                guard let data = image.pngData() else { continue }
                let outcome = await CapturePipeline.process(
                    imageData: data,
                    source: .screenshot,
                    context: modelContext,
                    categories: categories
                )
                switch outcome {
                case .needsConfirmation(let draft):
                    if draft.amountCents > 0 { drafts.append(draft) }
                case .saved(let transaction):
                    var draft = TransactionDraft()
                    draft.kind = transaction.kind
                    draft.amountCents = transaction.amountCents
                    draft.merchant = transaction.merchant
                    draft.item = transaction.item
                    draft.categoryName = transaction.categoryName
                    draft.categoryID = transaction.categoryID
                    draft.occurredAt = transaction.occurredAt
                    draft.platform = transaction.platform
                    draft.source = .screenshot
                    draft.confidence = transaction.confidence
                    drafts.append(draft)
                    // 自动模式下已经入账的，从库里撤掉，统一走导入流程
                    RecordService.delete(transaction, in: modelContext)
                case .failed:
                    continue
                }
            }

            await MainActor.run {
                var importResult = ImportService.Result()
                importResult.detectedFormat = "截图识别"
                importResult.drafts = drafts
                result = importResult
                stagedDrafts = drafts
                isWorking = false
            }
        }
    }

    private func commit() {
        let existing = transactions.filter { !$0.isDeleted }
        var imported = 0
        var skipped = 0

        for draft in stagedDrafts {
            if case .suspected = DuplicateDetector.check(draft: draft, against: existing) {
                skipped += 1
                continue
            }
            RecordService.save(draft: draft, in: modelContext, categories: categories)
            imported += 1
        }

        Haptics.success()
        stagedDrafts = []
        result = nil
        dismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            AppRouter.shared.showToast(
                AppToast(
                    title: "已导入 \(imported) 笔",
                    subtitle: skipped > 0 ? "\(skipped) 笔疑似重复已跳过" : "可以在账单页查看",
                    symbol: "checkmark.circle.fill",
                    tint: Theme.brand
                ),
                autoDismissAfter: 2.6
            )
        }
    }
}
