//
//  RecordService.swift
//  简记
//
//  账单写入的唯一入口。所有新增 / 修改 / 撤销都要走这里，
//  以保证：查重指纹一致、商户规则被学习、小组件快照被刷新。
//

import Foundation
import SwiftData

@MainActor
enum RecordService {

    // MARK: - 新建

    @discardableResult
    static func save(
        draft: TransactionDraft,
        in context: ModelContext,
        categories: [Category]
    ) -> Transaction {
        let transaction = Transaction(
            kind: draft.kind,
            amountCents: draft.amountCents,
            merchant: draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            item: draft.item.trimmingCharacters(in: .whitespacesAndNewlines),
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryID: draft.categoryID ?? SeedData.category(named: draft.categoryName, in: categories)?.id,
            categoryName: draft.categoryName,
            occurredAt: draft.occurredAt,
            platform: draft.platform,
            account: draft.account,
            orderNumber: draft.orderNumber,
            source: draft.source,
            confidence: draft.confidence,
            imageHash: draft.imageHash
        )
        transaction.createdAt = .now
        transaction.updatedAt = .now
        transaction.refreshDedupeKey()
        context.insert(transaction)

        commit(context: context)
        learn(draft: draft, in: context)
        SnapshotWriter.refresh(in: context)
        return transaction
    }

    // MARK: - 修改

    static func update(
        _ transaction: Transaction,
        with draft: TransactionDraft,
        in context: ModelContext
    ) {
        let categoryChanged = transaction.categoryName != draft.categoryName

        transaction.kind = draft.kind
        transaction.amountCents = max(0, draft.amountCents)
        transaction.merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.item = draft.item.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.categoryName = draft.categoryName
        transaction.categoryID = draft.categoryID
        transaction.occurredAt = draft.occurredAt
        transaction.platform = draft.platform
        transaction.account = draft.account
        transaction.orderNumber = draft.orderNumber
        transaction.refreshDedupeKey()

        commit(context: context)

        if categoryChanged {
            learn(draft: draft, in: context)
        }
        SnapshotWriter.refresh(in: context)
    }

    /// 只改分类（确认面板里点一下分类就走这里）
    static func updateCategory(
        _ transaction: Transaction,
        categoryName: String,
        categoryID: UUID?,
        in context: ModelContext
    ) {
        transaction.categoryName = categoryName
        transaction.categoryID = categoryID
        transaction.updatedAt = .now
        commit(context: context)
        upsertMerchantRule(
            merchant: transaction.merchant,
            categoryID: categoryID,
            categoryName: categoryName,
            in: context
        )
        SnapshotWriter.refresh(in: context)
    }

    // MARK: - 删除 / 撤销

    static func delete(_ transaction: Transaction, in context: ModelContext) {
        context.delete(transaction)
        commit(context: context)
        SnapshotWriter.refresh(in: context)
    }

    static func delete(ids: [UUID], in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        for transaction in all where ids.contains(transaction.id) {
            context.delete(transaction)
        }
        commit(context: context)
        SnapshotWriter.refresh(in: context)
    }

    /// 撤销：把刚记的一笔删掉
    static func undo(_ transaction: Transaction, in context: ModelContext) {
        delete(transaction, in: context)
    }

    // MARK: - 商户学习

    static func learn(draft: TransactionDraft, in context: ModelContext) {
        upsertMerchantRule(
            merchant: draft.merchant,
            categoryID: draft.categoryID,
            categoryName: draft.categoryName,
            in: context
        )
    }

    static func upsertMerchantRule(
        merchant: String,
        categoryID: UUID?,
        categoryName: String,
        in context: ModelContext
    ) {
        let pattern = TextNormalizer.normalize(merchant)
        guard pattern.count >= 2 else { return }

        let all = (try? context.fetch(FetchDescriptor<MerchantRule>())) ?? []
        if let existing = all.first(where: { $0.pattern == pattern }) {
            existing.categoryID = categoryID
            existing.categoryName = categoryName
            existing.hitCount += 1
            existing.lastUsedAt = .now
        } else {
            let rule = MerchantRule(
                pattern: pattern,
                displayName: merchant,
                categoryID: categoryID,
                categoryName: categoryName
            )
            context.insert(rule)
        }
        commit(context: context)
    }

    // MARK: - 提交

    private static func commit(context: ModelContext) {
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("[简记] 保存失败：\(error)")
            #endif
        }
    }
}
