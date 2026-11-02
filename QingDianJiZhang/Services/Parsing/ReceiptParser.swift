//
//  ReceiptParser.swift
//  简记
//
//  从 OCR 文本里解析出：金额 / 商户 / 商品 / 时间 / 平台 / 订单号 / 收支方向。
//
//  这是全 App 最关键的模块之一。策略是「关键词优先级 + 位置约束 + 合理性校验」，
//  而不是单纯抓第一个数字——支付截图里同时存在「优惠金额」「订单金额」「实付金额」，
//  抓错一个就会记成完全错误的账。
//

import Foundation

// MARK: - 解析结果

struct ParsedReceipt {
    var kind: TransactionKind = .expense
    /// 收支方向的置信度。低于 0.7 时 UI 会让用户先选收入/支出。
    var kindConfidence: Double = 0.0

    var amountCents: Int?
    var merchant: String = ""
    var item: String = ""
    var occurredAt: Date = .now
    var didParseDate: Bool = false

    var platform: PaymentPlatform = .other
    var account: String = ""
    var orderNumber: String = ""

    var rawText: String = ""
    var confidence: Double = 0.0
    /// 解析过程记录，用于「识别详情」调试面板
    var notes: [String] = []

    var hasUsableAmount: Bool { (amountCents ?? 0) > 0 }
    var amountYuanText: String { MoneyFormatter.string(cents: amountCents ?? 0) }
}

// MARK: - 解析器

enum ReceiptParser {

    // MARK: 金额

    /// 关键词权重，越大越接近「真正的实付金额」
    private static let amountKeywords: [(keyword: String, weight: Int)] = [
        ("实付款", 100), ("实付", 100), ("实际支付", 100), ("实际付款", 100), ("已付款", 96),
        ("退款金额", 96), ("退款", 92),
        ("支付金额", 95), ("付款金额", 95), ("交易金额", 92), ("订单金额", 90),
        ("应付金额", 88), ("消费金额", 88), ("扣款金额", 88), ("本期应还", 80),
        ("小计", 72), ("合计", 68), ("总计", 66), ("总额", 62), ("金额", 52),
        ("支付", 44), ("付款", 44), ("消费", 40), ("扣款", 40)
    ]

    /// 明显不是金额的关键词（避免把「优惠 -2.00」当成实付）
    private static let discountKeywords = [
        "优惠", "折扣", "立减", "红包抵扣", "券", "减免", "返现", "余额",
        "积分", "手续费", "服务费", "找零", "抹零"
    ]

    private static let merchantBlacklist: [String] = [
        "支付成功", "付款成功", "交易成功", "支付完成", "已支付", "付款成功页",
        "账单详情", "订单详情", "微信支付", "支付宝", "云闪付", "apple pay",
        "收银台", "确认付款", "立即支付", "查看详情", "查看更多", "交易单号",
        "商户单号", "订单号", "订单编号", "账单", "合计", "总计", "实付", "金额",
        "优惠", "退款", "客服", "帮助中心", "支付方式", "付款方式", "商品", "数量",
        "单价", "时间", "备注", "我的", "首页", "恭喜", "完成", "返回", "银联",
        "银行卡", "订单", "详情", "全部", "收起", "复制", "分享", "评价", "再来一单",
        "查看账单", "安全保障", "中国大陆", "服务中心", "发票", "联系商家", "申请售后",
        "积分", "余额", "零钱", "钱包", "收款方", "付款方", "转账", "银行",
        // 钱包流水页的标签词，OCR 后常常单独成行，容易被误判成商户
        "类型", "状态", "说明", "明细", "零钱明细", "交易详情", "退款详情", "账单详情", "全部账单"
    ]

    private static let merchantSuffixHints = [
        "店", "餐厅", "饭馆", "超市", "公司", "有限", "酒店", "咖啡", "商城", "商行",
        "影院", "药房", "药店", "医院", "门诊", "中心", "广场", "大厦", "集团", "食品",
        "便利店", "菜馆", "酒家", "茶", "馆", "坊", "铺", "站", "行", "社", "堂", "轩"
    ]

    // MARK: 主入口

    static func parse(document: OCRDocument, now: Date = .now) -> ParsedReceipt {
        parse(lines: document.orderedLines.map(\.text), now: now)
    }

    static func parse(text: String, now: Date = .now) -> ParsedReceipt {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parse(lines: lines, now: now)
    }

    static func parse(lines: [String], now: Date = .now) -> ParsedReceipt {
        var result = ParsedReceipt()
        result.rawText = lines.joined(separator: "\n")
        let joined = result.rawText

        // 1. 收支方向
        let kindResult = detectKind(in: joined)
        result.kind = kindResult.kind
        result.kindConfidence = kindResult.confidence
        result.notes.append("收支方向：\(kindResult.kind.title)（置信度 \(String(format: "%.2f", kindResult.confidence))，依据：\(kindResult.reason)）")

        // 2. 金额
        result.amountCents = extractAmount(lines: lines, notes: &result.notes)

        // 3. 商户
        result.merchant = extractMerchant(lines: lines, notes: &result.notes)

        // 4. 商品 / 订单内容
        result.item = extractItem(lines: lines, merchant: result.merchant)

        // 5. 时间
        let dateResult = extractDate(in: joined, now: now)
        result.occurredAt = dateResult.date
        result.didParseDate = dateResult.parsed

        // 6. 支付平台 / 账户
        result.platform = detectPlatform(in: joined)
        result.account = extractAccount(in: joined)

        // 7. 订单号
        result.orderNumber = extractOrderNumber(in: joined)
        if !result.orderNumber.isEmpty {
            result.notes.append("订单号：\(result.orderNumber)")
        }

        // 8. 综合置信度
        result.confidence = overallConfidence(result)
        return result
    }

    // MARK: - 收支方向

    private static let incomeKeywords = [
        "收款成功", "已收款", "收款到账", "收款", "收入", "退款成功", "已退款", "退款到账",
        "退款", "退回", "退货退款",
        "工资", "薪资", "奖金", "红包到账", "到账", "入账", "转入", "返现", "提现"
    ]

    private static let expenseKeywords = [
        "支付成功", "付款成功", "交易成功", "已支付", "实付", "付款", "支付",
        "消费", "扣款", "支出", "转出", "已扣款", "完成支付"
    ]

    private static func detectKind(in text: String) -> (kind: TransactionKind, confidence: Double, reason: String) {
        let normalized = TextNormalizer.normalize(text)
        let incomeHits = incomeKeywords.filter { normalized.contains(TextNormalizer.normalize($0)) }
        let expenseHits = expenseKeywords.filter { normalized.contains(TextNormalizer.normalize($0)) }

        // 「退款」优先级最高：退款一定是收入
        if normalized.contains("退款成功") || normalized.contains("已退款") || normalized.contains("退款到账")
            || normalized.contains("退货退款") {
            return (.income, 0.95, "命中退款关键词")
        }

        // 金额前带正负号（零钱明细、银行流水的标准写法）：「+4.00」必然是收入
        if let signed = detectSignedKind(in: text) {
            return signed
        }

        if incomeHits.count > expenseHits.count {
            let confidence = min(0.95, 0.68 + Double(incomeHits.count) * 0.06)
            return (.income, confidence, "命中「\(incomeHits.first ?? "")」")
        }
        if expenseHits.count > incomeHits.count {
            let confidence = min(0.96, 0.72 + Double(expenseHits.count) * 0.05)
            return (.expense, confidence, "命中「\(expenseHits.first ?? "")」")
        }
        if expenseHits.isEmpty && incomeHits.isEmpty {
            return (.expense, 0.45, "没有明确方向关键词")
        }
        return (.expense, 0.55, "收支关键词数量相当")
    }

    /// 整行就是「+4.00」「-12.80」这种带符号金额时，符号本身就是最可靠的方向依据
    private static func detectSignedKind(in text: String) -> (kind: TransactionKind, confidence: Double, reason: String)? {
        let pattern = #"^[+＋\-－]\s*[¥￥]?\s*\d"#
        var plus = 0
        var minus = 0
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("+") || line.hasPrefix("＋") {
                if RegexHelper.contains(pattern, in: line) { plus += 1 }
            } else if line.hasPrefix("-") || line.hasPrefix("－") {
                if RegexHelper.contains(pattern, in: line) { minus += 1 }
            }
        }
        if plus > 0 && minus == 0 { return (.income, 0.90, "金额前缀为 + 号") }
        if minus > 0 && plus == 0 { return (.expense, 0.90, "金额前缀为 − 号") }
        return nil
    }

    // MARK: - 金额

    /// 先清掉日期、时间、订单号等干扰数字，再按关键词优先级取金额
    private static func cleaned(_ line: String) -> String {
        var text = line
        text = RegexHelper.blankOut(#"\d{4}\s*[-/年.]\s*\d{1,2}\s*[-/月.]\s*\d{1,2}\s*日?"#, in: text)
        text = RegexHelper.blankOut(#"\d{1,2}\s*[-/月]\s*\d{1,2}\s*日?"#, in: text)
        text = RegexHelper.blankOut(#"\d{1,2}:\d{2}(:\d{2})?"#, in: text)
        text = RegexHelper.blankOut(#"\d{3,4}-\d{7,8}"#, in: text)
        text = RegexHelper.blankOut(#"[A-Za-z0-9]{14,}"#, in: text)
        text = RegexHelper.blankOut(#"\d{9,}"#, in: text)
        return text
    }

    private struct AmountToken {
        let cents: Int
        let range: Range<String.Index>
        let hasSymbol: Bool
        let hasYuanSuffix: Bool
        /// 带小数（"4.00"）比裸整数（"9895"）更可能是金额，而不是单号碎片
        let hasFraction: Bool
    }

    private static func amountTokens(in text: String) -> [AmountToken] {
        let pattern = #"(?:¥|￥|RMB|CNY)?\s*(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)\s*(元|块)?"#
        let matches = RegexHelper.matches(pattern, in: text)
        return matches.compactMap { match in
            guard let digitsGroup = match.groups.first, let digits = digitsGroup else { return nil }
            guard let cents = MoneyFormatter.cents(fromYuanText: digits) else { return nil }
            // 合理区间：1 分 ~ 100 万元
            guard cents >= 1, cents <= 100_000_000 else { return nil }
            // 货币符号在正则里属于匹配内容，不能用「匹配前的字符」判断，否则永远为 false
            let upperValue = match.value.uppercased()
            let hasSymbol = match.value.contains("¥") || match.value.contains("￥")
                || upperValue.contains("RMB") || upperValue.contains("CNY")
            let suffix = match.groups.count > 1 ? (match.groups[1] ?? "") : ""
            return AmountToken(
                cents: cents,
                range: match.range,
                hasSymbol: hasSymbol,
                hasYuanSuffix: !suffix.isEmpty,
                hasFraction: digits.contains(".")
            )
        }
    }

    private static func extractAmount(lines: [String], notes: inout [String]) -> Int? {
        struct Candidate {
            let cents: Int
            let score: Int
            let source: String
        }
        var candidates: [Candidate] = []
        /// 通过「非单号、非余额」筛选后的金额，供兜底使用
        var safeTokens: [AmountToken] = []

        // 单独一行、且带正负号：「+4.00」「-12.80」，退款与流水页面的标准写法
        let signedLinePattern = #"^[+＋\-－]\s*[¥￥]?\s*[\d,]+(?:\.\d{1,2})?$"#

        for (index, line) in lines.enumerated() {
            let clean = cleaned(line)
            guard !clean.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            // 整行是单号 / 流水号：直接作废，避免把号码尾数当成金额
            guard !looksLikeOrderNumber(clean) else {
                notes.append("跳过疑似单号行：\(line)")
                continue
            }

            let tokens = amountTokens(in: clean)
            guard !tokens.isEmpty else { continue }

            let lowered = TextNormalizer.normalize(clean)
            let previousLine = index > 0 ? TextNormalizer.normalize(lines[index - 1]) : ""
            // 「余额」标签和数值常常分两行，需要用上一行判断这个数字属于余额
            let isBalanceLine = lowered.contains("余额") || lowered.contains("可用额度")
                || previousLine == "余额" || previousLine == "可用额度"
            let isDiscountLine = isBalanceLine
                || discountKeywords.contains { lowered.contains(TextNormalizer.normalize($0)) }

            if !isBalanceLine {
                safeTokens.append(contentsOf: tokens)
            }

            let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
            if !isDiscountLine,
               RegexHelper.contains(signedLinePattern, in: trimmed),
               let token = tokens.first {
                candidates.append(Candidate(cents: token.cents, score: 98, source: line))
            }

            for entry in amountKeywords {
                // 用原始字符串定位关键词，保证索引和金额 token 处在同一坐标系
                guard let keyRange = clean.range(of: entry.keyword, options: .caseInsensitive) else {
                    continue
                }
                // 关键词之后出现的第一个数字，才是这个关键词对应的金额
                guard let firstAfter = tokens.first(where: { $0.range.lowerBound >= keyRange.upperBound })
                    ?? tokens.last else {
                    continue
                }
                var score = entry.weight
                if isDiscountLine { score -= 120 }
                if firstAfter.hasSymbol { score += 6 }
                if firstAfter.hasYuanSuffix { score += 3 }
                candidates.append(Candidate(cents: firstAfter.cents, score: score, source: line))
            }

            // 没有命中任何关键词，但有 ¥ 符号的行也作为低权重候选
            if !isDiscountLine, let symbolToken = tokens.first(where: { $0.hasSymbol }) {
                candidates.append(Candidate(cents: symbolToken.cents, score: 30, source: line))
            }
        }

        if let best = candidates.max(by: { $0.score < $1.score }), best.score > 0 {
            notes.append("金额来源：\(best.source)（权重 \(best.score)）")
            return best.cents
        }

        // 兜底不再「取全文最大数字」：只接受带货币符号、带「元」或带小数的金额。
        // 宁可返回空让用户手填，也不要把单号碎片记成一笔错账。
        let usable = safeTokens.filter { $0.hasSymbol || $0.hasYuanSuffix || $0.hasFraction }
        if let best = usable.max(by: { $0.cents < $1.cents }) {
            notes.append("金额兜底：取带符号或小数的最大金额 \(MoneyFormatter.string(cents: best.cents))")
            return best.cents
        }
        notes.append("未识别到可信金额，请手动填写")
        return nil
    }

    /// 单号 / 流水号 / 12 位以上长数字：不可能是金额
    private static func looksLikeOrderNumber(_ text: String) -> Bool {
        let digits = text.filter { $0.isNumber }
        guard !digits.isEmpty else { return false }
        if digits.count >= 12 { return true }
        let hasLabel = ["单号", "订单", "流水", "凭证", "交易号", "编号"].contains { text.contains($0) }
        return hasLabel && digits.count >= 8
    }

    // MARK: - 商户

    private static func extractMerchant(lines: [String], notes: inout [String]) -> String {
        // 1) 明确标签：商户 / 收款方 / 商家 —— 标签后面的值最可信
        let labelPrefixes = ["商户名称", "商户全称", "交易对方", "收款方", "商家名称", "商户", "商家", "对方"]
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in labelPrefixes where line.hasPrefix(prefix) {
                var value = String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " :：-—|·、,，"))
                if value.isEmpty, index + 1 < lines.count {
                    value = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let merchantName = cleanMerchant(value)
                if isPlausibleMerchant(merchantName) {
                    notes.append("商户来源：标签「\(prefix)」")
                    return merchantName
                }
            }
        }

        // 2) 备注：微信零钱明细、银行流水常常只给「备注」，里面才是真正的商户或用途
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("备注") else { continue }
            var value = String(line.dropFirst(2))
                .trimmingCharacters(in: CharacterSet(charactersIn: " :：-—|·、,，"))
            if value.isEmpty, index + 1 < lines.count {
                value = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let merchantName = cleanMerchant(value)
            if isPlausibleMerchant(merchantName) {
                notes.append("商户来源：备注")
                return merchantName
            }
        }

        // 3) 评分兜底
        struct Candidate {
            let text: String
            let score: Double
        }
        var candidates: [Candidate] = []
        let total = max(lines.count, 1)

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.count >= 2, line.count <= 40 else { continue }
            // OCR 乱码（如「£! 今®9」）与纯标签词在这里就被挡掉
            guard isPlausibleMerchant(line) else { continue }
            let cjkCount = line.unicodeScalars.filter { $0.properties.isIdeographic }.count
            guard cjkCount >= 3 else { continue }

            let positionRatio = Double(index) / Double(total)
            let lowered = TextNormalizer.normalize(line)

            var score = 0.0
            if merchantBlacklist.contains(where: { lowered.contains(TextNormalizer.normalize($0)) }) {
                score -= 10
            }
            if BrandLexicon.containsKnownBrand(line) { score += 2.4 }
            if merchantSuffixHints.contains(where: { line.contains($0) }) { score += 1.3 }
            if positionRatio < 0.45 { score += 0.9 }
            if positionRatio > 0.85 { score -= 0.6 }
            if line.contains("¥") || line.contains("￥") { score -= 1.2 }
            if RegexHelper.contains(#"\d{1,2}:\d{2}"#, in: line) { score -= 3 }
            if RegexHelper.contains(#"\d{4}[-/年]"#, in: line) { score -= 3 }

            let digits = line.filter { $0.isNumber }
            if digits.count > 3 { score -= 1.6 }
            if line.count >= 2 && line.count <= 22 { score += 0.5 }
            if line.unicodeScalars.contains(where: { $0.properties.isIdeographic }) { score += 0.4 }
            if line.hasPrefix("商户") || line.hasPrefix("收款方") { score += 1.2 }

            if score > 0 {
                candidates.append(Candidate(text: cleanMerchant(line), score: score))
            }
        }

        if let best = candidates.max(by: { $0.score < $1.score }), !best.text.isEmpty {
            notes.append("商户来源评分：\(String(format: "%.1f", best.score))")
            return best.text
        }
        notes.append("未识别到商户名")
        return ""
    }

    /// 商户名的最低可信标准：长度合理、可读字符占比够、不是纯标签词
    private static func isPlausibleMerchant(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 40 else { return false }
        let lowered = TextNormalizer.normalize(trimmed)
        guard !lowered.isEmpty else { return false }
        if merchantBlacklist.contains(where: { lowered == TextNormalizer.normalize($0) }) { return false }
        // 「商户单号 123456」这类标签行会被前缀匹配误当成商户，这里直接排除
        let blockedTokens = ["单号", "编号", "流水", "凭证", "订单号", "交易号"]
        if blockedTokens.contains(where: { trimmed.contains($0) }) { return false }

        let scalars = Array(trimmed.unicodeScalars)
        let readable = scalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0.properties.isIdeographic
        }.count
        // 乱码行（£ ! ® 之类）可读字符占比很低，直接丢弃
        guard Double(readable) / Double(max(scalars.count, 1)) >= 0.6 else { return false }

        let cjkCount = scalars.filter { $0.properties.isIdeographic }.count
        return cjkCount >= 2 || BrandLexicon.containsKnownBrand(trimmed)
    }

    private static func cleanMerchant(_ line: String) -> String {
        var text = line
        for prefix in ["商户名称", "商户全称", "收款方", "商户", "商家名称", "商家", "交易对方", "名称", "备注"] {
            if text.hasPrefix(prefix) {
                text.removeFirst(prefix.count)
            }
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " :：-—|·、,，"))
        // 「京津冀互联互通卡 充值」这类备注，末尾的动作词不是商户名的一部分
        for suffix in ["充值", "消费", "支付", "付款", "转账", "退款", "扣款"] {
            if text.hasSuffix(suffix), text.count > suffix.count + 1 {
                text = String(text.dropLast(suffix.count))
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 24 {
            text = String(text.prefix(24))
        }
        return text
    }

    // MARK: - 商品

    private static func extractItem(lines: [String], merchant: String) -> String {
        let itemKeywords = ["商品名称", "商品", "订单内容", "订单商品", "消费项目", "项目", "内容", "套餐"]

        for line in lines {
            for keyword in itemKeywords {
                guard let range = line.range(of: keyword) else { continue }
                var value = String(line[range.upperBound...])
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: " :：-—|·"))
                if value.count >= 2, !value.hasPrefix("¥") {
                    return String(value.prefix(40))
                }
            }
        }

        // 找不到显式字段时，取商户行之后的第一条有效文本
        if let index = lines.firstIndex(where: { $0.contains(merchant) && !merchant.isEmpty }),
           index + 1 < lines.count {
            let next = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = TextNormalizer.normalize(next)
            let blocked = merchantBlacklist.contains { lowered.contains(TextNormalizer.normalize($0)) }
            if !blocked, next.count >= 2, next.count <= 30, !next.contains("¥") {
                return next
            }
        }
        return ""
    }

    // MARK: - 时间

    private static func extractDate(in text: String, now: Date) -> (date: Date, parsed: Bool) {
        let calendar = Calendar(identifier: .gregorian)
        let pattern = #"(\d{4})\s*[-/年.]\s*(\d{1,2})\s*[-/月.]\s*(\d{1,2})\s*日?\s*(?:(\d{1,2})[:：](\d{2}))?"#

        if let match = RegexHelper.firstMatch(pattern, in: text),
           match.groups.count >= 3,
           let year = Int(match.groups[0] ?? ""),
           let month = Int(match.groups[1] ?? ""),
           let day = Int(match.groups[2] ?? "") {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            comps.hour = Int(match.groups.count > 3 ? (match.groups[3] ?? "0") : "0") ?? 0
            comps.minute = Int(match.groups.count > 4 ? (match.groups[4] ?? "0") : "0") ?? 0
            if let date = calendar.date(from: comps), date <= now.addingTimeInterval(86_400) {
                return (date, true)
            }
        }

        // 只有时间（例如「14:32」）：用今天 + 该时间
        if let timeMatch = RegexHelper.firstMatch(#"(\d{1,2})[:：](\d{2})(?::\d{2})?"#, in: text) {
            let hourText: String? = timeMatch.groups.first ?? nil
            let minuteText: String? = timeMatch.groups.count > 1 ? (timeMatch.groups[1] ?? nil) : nil
            if let hour = hourText.flatMap(Int.init),
               let minute = minuteText.flatMap(Int.init),
               hour < 24, minute < 60 {
                var comps = calendar.dateComponents([.year, .month, .day], from: now)
                comps.hour = hour
                comps.minute = minute
                if let date = calendar.date(from: comps) {
                    return (date, true)
                }
            }
        }

        // NSDataDetector 兜底
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            if let result = detector.firstMatch(in: text, options: [], range: range),
               let date = result.date, date <= now.addingTimeInterval(86_400) {
                return (date, true)
            }
        }

        return (now, false)
    }

    // MARK: - 平台

    private static func detectPlatform(in text: String) -> PaymentPlatform {
        let lowered = TextNormalizer.normalize(text)
        if lowered.contains("微信支付") || lowered.contains("wxpay") || lowered.contains("微信") && lowered.contains("支付") {
            return .wechat
        }
        if lowered.contains("支付宝") || lowered.contains("alipay") || lowered.contains("花呗") || lowered.contains("余额宝") {
            return .alipay
        }
        if lowered.contains("云闪付") || lowered.contains("银联") {
            return .unionPay
        }
        if lowered.contains("applepay") || lowered.contains("apple pay") {
            return .applePay
        }
        if lowered.contains("储蓄卡") || lowered.contains("信用卡") || lowered.contains("借记卡")
            || lowered.contains("招商银行") || lowered.contains("工商银行") || lowered.contains("建设银行")
            || lowered.contains("农业银行") || lowered.contains("中国银行") || lowered.contains("交通银行")
            || lowered.contains("民生银行") || lowered.contains("浦发银行") || lowered.contains("兴业银行") {
            return .bankCard
        }
        return .other
    }

    private static func extractAccount(in text: String) -> String {
        let pattern = #"(储蓄卡|信用卡|借记卡|银行卡)[^\d]{0,8}(\d{4})"#
        if let match = RegexHelper.firstMatch(pattern, in: text) {
            let type = match.groups.first.flatMap { $0 } ?? "银行卡"
            let tail = match.groups.count > 1 ? (match.groups[1] ?? "") : ""
            return tail.isEmpty ? type : "\(type)(\(tail))"
        }
        let banks = ["招商银行", "工商银行", "建设银行", "农业银行", "中国银行", "交通银行",
                     "民生银行", "浦发银行", "兴业银行", "中信银行", "光大银行", "平安银行"]
        if let bank = banks.first(where: { text.contains($0) }) {
            return bank
        }
        return ""
    }

    // MARK: - 订单号

    private static func extractOrderNumber(in text: String) -> String {
        let pattern = #"(?:订单(?:编)?号|交易单号|商户单号|交易号|流水号|凭证号)\s*[:：]?\s*([A-Za-z0-9]{8,40})"#
        if let match = RegexHelper.firstMatch(pattern, in: text) {
            return match.groups.first.flatMap { $0 } ?? ""
        }
        return ""
    }

    // MARK: - 综合置信度

    private static func overallConfidence(_ result: ParsedReceipt) -> Double {
        var score = 0.10
        if result.hasUsableAmount { score += 0.38 }
        if !result.merchant.isEmpty { score += 0.20 }
        if result.kindConfidence >= 0.8 { score += 0.10 }
        if result.platform != .other { score += 0.08 }
        if result.didParseDate { score += 0.05 }
        if !result.orderNumber.isEmpty { score += 0.05 }
        if result.amountCents == nil { score -= 0.25 }
        return min(max(score, 0.05), 0.99)
    }
}
