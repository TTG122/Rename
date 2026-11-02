//
//  DuplicateDetector.swift
//  轻点记账
//
//  重复记账检测。宁可多问一句，也不要记成两笔——用户发现重复比发现漏记更难修。
//

import Foundation

enum DuplicateVerdict: Equatable {
    case unique
    case suspected(existingID: UUID, existingTitle: String, existingAmountText: String, score: Double, reason: String)

    var isSuspected: Bool {
        if case .suspected = self { return true }
        return false
    }
}

enum DuplicateDetector {

    /// 判定阈值。超过就提示「这笔账单可能已经记录」
    static let threshold: Double = 0.72

    static func check(
        draft: TransactionDraft,
        against transactions: [Transaction],
        threshold: Double = DuplicateDetector.threshold
    ) -> DuplicateVerdict {
        guard draft.amountCents > 0 else { return .unique }

        // 只在 ±7 天内比较，避免全表扫描
        let window: TimeInterval = 7 * 24 * 3600
        let nearby = transactions.filter {
            !$0.isDeleted && abs($0.occurredAt.timeIntervalSince(draft.occurredAt)) <= window
        }
        guard !nearby.isEmpty else { return .unique }

        var best: (transaction: Transaction, score: Double, reason: String)?

        for candidate in nearby {
            let evaluation = score(draft: draft, candidate: candidate)
            guard evaluation.score >= threshold else { continue }
            if best == nil || evaluation.score > best!.score {
                best = (candidate, evaluation.score, evaluation.reason)
            }
        }

        guard let best else { return .unique }
        return .suspected(
            existingID: best.transaction.id,
            existingTitle: best.transaction.displayTitle,
            existingAmountText: best.transaction.signedAmountText,
            score: best.score,
            reason: best.reason
        )
    }

    // MARK: - 打分

    private static func score(draft: TransactionDraft, candidate: Transaction) -> (score: Double, reason: String) {
        // 1. 订单号相同 → 一定是同一笔
        if !draft.orderNumber.isEmpty,
           !candidate.orderNumber.isEmpty,
           draft.orderNumber == candidate.orderNumber {
            return (1.0, "订单号相同")
        }

        // 2. 图片字节指纹相同
        if !draft.imageHash.isEmpty, draft.imageHash == candidate.imageHash {
            return (0.97, "同一张截图")
        }

        // 3. 感知指纹相近（截图被重新压缩过）
        if !draft.perceptualHash.isEmpty, !candidate.imageHash.isEmpty {
            let candidatePerceptual = candidate.imageHash
            if candidatePerceptual.count == draft.perceptualHash.count {
                let distance = ImageHash.hammingDistance(draft.perceptualHash, candidatePerceptual)
                if distance <= 4 {
                    return (0.8, "截图内容高度相似")
                }
            }
        }

        let sameAmount = draft.amountCents == candidate.amountCents
        guard sameAmount else { return (0, "") }

        let normalizedDraftMerchant = TextNormalizer.normalize(draft.merchant)
        let normalizedCandidateMerchant = TextNormalizer.normalize(candidate.merchant)
        let sameMerchant = !normalizedDraftMerchant.isEmpty
            && normalizedDraftMerchant == normalizedCandidateMerchant
        let timeDelta = abs(candidate.occurredAt.timeIntervalSince(draft.occurredAt))

        if sameMerchant && timeDelta <= 300 {
            return (0.94, "金额、商户、时间都一致")
        }
        if sameMerchant && timeDelta <= 3600 {
            return (0.78, "同一商户一小时内有相同金额")
        }
        if timeDelta <= 120 {
            return (0.76, "两分钟内出现相同金额")
        }
        if sameMerchant {
            return (0.6, "同一商户出现相同金额")
        }
        return (0, "")
    }
}
