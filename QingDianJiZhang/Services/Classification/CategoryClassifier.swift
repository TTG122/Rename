//
//  CategoryClassifier.swift
//  轻点记账
//
//  三级分类策略，按优先级：
//  1. 用户历史规则（MerchantRule）：用户改过一次，以后就记住 —— 置信度 0.97
//  2. 本机 Core ML 文本分类模型（可选，存在才用）
//  3. 品牌关键词词典 + 权重打分 —— 兜底，覆盖绝大多数场景
//
//  全部在设备本地完成，不联网。
//

import Foundation
import CoreML
import NaturalLanguage

// MARK: - 输入

struct ClassificationInput {
    var merchant: String
    var item: String
    var rawText: String
    var kind: TransactionKind
    /// 归一化商户 → 分类名
    var learnedRules: [String: String]
    /// 当前可用分类名（用户可能新建/删除分类）
    var availableCategories: [String]

    init(
        merchant: String,
        item: String,
        rawText: String,
        kind: TransactionKind,
        learnedRules: [String: String] = [:],
        availableCategories: [String] = SystemCategories.all.map(\.name)
    ) {
        self.merchant = merchant
        self.item = item
        self.rawText = rawText
        self.kind = kind
        self.learnedRules = learnedRules
        self.availableCategories = availableCategories
    }
}

// MARK: - 协议

protocol CategoryClassifying {
    func classify(_ input: ClassificationInput) -> ClassificationResult
}

// MARK: - 规则分类器

struct RuleBasedClassifier: CategoryClassifying {
    func classify(_ input: ClassificationInput) -> ClassificationResult {
        // 1. 历史规则
        let normalizedMerchant = TextNormalizer.normalize(input.merchant)
        if !normalizedMerchant.isEmpty {
            if let learned = input.learnedRules[normalizedMerchant] {
                return ClassificationResult(
                    categoryName: resolved(learned, for: input),
                    confidence: 0.97,
                    reason: "你之前把「\(input.merchant)」设成了\(learned)"
                )
            }
            // 部分匹配：商户名带门店后缀时也能命中
            for (pattern, category) in input.learnedRules
            where !pattern.isEmpty && (normalizedMerchant.contains(pattern) || pattern.contains(normalizedMerchant)) {
                return ClassificationResult(
                    categoryName: resolved(category, for: input),
                    confidence: 0.9,
                    reason: "历史上「\(input.merchant)」属于\(category)"
                )
            }
        }

        // 2. 关键词打分。商户名权重更高
        var scores: [String: Double] = [:]
        let merchantHits = BrandLexicon.allCategoryHits(in: input.merchant)
        for (category, score) in merchantHits {
            scores[category, default: 0] += score * 1.8
        }
        let itemHits = BrandLexicon.allCategoryHits(in: input.item)
        for (category, score) in itemHits {
            scores[category, default: 0] += score * 1.1
        }
        let textHits = BrandLexicon.allCategoryHits(in: input.rawText)
        for (category, score) in textHits {
            scores[category, default: 0] += score * 0.55
        }

        // 3. 按收支方向过滤
        var best: (category: String, score: Double)?
        for (category, score) in scores {
            guard isCategory(category, compatibleWith: input.kind) else { continue }
            if best == nil || score > best!.score {
                best = (category, score)
            }
        }

        if let best {
            let confidence = min(0.95, 0.55 + best.score * 0.12)
            let source = merchantHits[best.category] != nil ? "商户名" : "订单内容"
            return ClassificationResult(
                categoryName: resolved(best.category, for: input),
                confidence: confidence,
                reason: "\(source)命中「\(best.category)」相关关键词"
            )
        }

        // 4. 兜底
        if input.kind == .income {
            return ClassificationResult(
                categoryName: resolved("工资收入", for: input),
                confidence: 0.3,
                reason: "没有匹配到具体分类，先按收入归类"
            )
        }
        return ClassificationResult(
            categoryName: resolved("其他", for: input),
            confidence: 0.25,
            reason: "没有匹配到分类规则，请手动选择"
        )
    }

    private func isCategory(_ name: String, compatibleWith kind: TransactionKind) -> Bool {
        if kind == .income {
            return name == "工资收入" || name == "其他"
        }
        return name != "工资收入"
    }

    /// 把词典里的分类名映射到用户当前实际存在的分类
    private func resolved(_ name: String, for input: ClassificationInput) -> String {
        if input.availableCategories.contains(name) { return name }
        // 生活缴费 → 水电 这类别名
        let aliases: [String: [String]] = [
            "水电": ["生活缴费", "缴费"],
            "吃饭": ["餐饮", "食品"],
            "工资收入": ["收入", "薪资"]
        ]
        if let candidates = aliases[name] {
            if let hit = candidates.first(where: { input.availableCategories.contains($0) }) {
                return hit
            }
        }
        return input.availableCategories.contains("其他") ? "其他" : (input.availableCategories.first ?? "其他")
    }
}

// MARK: - Core ML 文本分类器（可选增强）

/// 如果工程里放了 `QingDianTextClassifier.mlmodelc`（由 tools/train_text_classifier.swift 生成），
/// 就会自动启用；没有则完全走规则，不影响功能。
struct CoreMLTextClassifier {
    private let model: NLModel?

    init() {
        model = try? NLModel(mlModel: Self.loadCompiledModel())
    }

    private static func loadCompiledModel() throws -> MLModel {
        guard let url = Bundle.main.url(forResource: "QingDianTextClassifier", withExtension: "mlmodelc") else {
            throw NSError(domain: "QingDianJiZhang", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "未找到本地分类模型"
            ])
        }
        return try MLModel(contentsOf: url)
    }

    var isAvailable: Bool { model != nil }

    func predict(text: String) -> ClassificationResult? {
        guard let model else { return nil }
        guard let label = model.predictedLabel(for: text) else { return nil }
        let hypotheses = model.predictedLabelHypotheses(for: text, maximumCount: 3)
        let confidence = hypotheses[label] ?? 0.6
        guard confidence >= 0.45 else { return nil }
        return ClassificationResult(
            categoryName: label,
            confidence: min(confidence, 0.93),
            reason: "本地模型判断"
        )
    }
}

// MARK: - 组合分类器

struct HybridClassifier: CategoryClassifying {
    private let rules = RuleBasedClassifier()
    private let ml = CoreMLTextClassifier()

    func classify(_ input: ClassificationInput) -> ClassificationResult {
        // 历史规则优先
        let ruleResult = rules.classify(input)
        if ruleResult.confidence >= 0.9 { return ruleResult }

        // 模型可用且更自信时采用模型结果
        if let mlResult = ml.predict(text: "\(input.merchant) \(input.item) \(input.rawText)"),
           mlResult.confidence > ruleResult.confidence,
           input.availableCategories.contains(mlResult.categoryName) {
            return mlResult
        }
        return ruleResult
    }
}

// MARK: - 学习规则

enum MerchantLearning {
    /// 从已保存的账单还原「商户 → 分类」规则表
    static func rules(from transactions: [Transaction]) -> [String: String] {
        var result: [String: String] = [:]
        for transaction in transactions {
            let key = TextNormalizer.normalize(transaction.merchant)
            guard key.count >= 2 else { continue }
            // 后写入的（更新的）覆盖旧的
            result[key] = transaction.categoryName
        }
        return result
    }

    static func rules(from merchantRules: [MerchantRule]) -> [String: String] {
        var result: [String: String] = [:]
        for rule in merchantRules.sorted(by: { $0.lastUsedAt < $1.lastUsedAt }) {
            result[rule.pattern] = rule.categoryName
        }
        return result
    }
}

extension CoreMLTextClassifier {
    /// 模型是否已就绪（设置页展示用）
    var statusText: String { isAvailable ? "已启用" : "使用规则引擎" }
}
