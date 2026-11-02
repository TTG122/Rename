//
//  VoiceCommandParser.swift
//  轻点记账
//
//  语音/文字指令解析：「今天中午吃饭花了28元」→ 支出 28 元 · 吃饭 · 今天 12:00
//  纯本地规则，不联网，也不需要任何语音服务额度。
//

import Foundation

enum VoiceCommandParser {

    private static let incomeVerbs = ["收到", "收款", "进账", "到账", "赚了", "发了工资", "报销", "退款", "入账"]
    private static let expenseVerbs = ["花了", "消费", "花了钱", "付了", "支付", "花了", "充了", "买了", "交了", "打车", "吃了", "喝了"]

    static func parse(text: String, now: Date = .now) -> ParsedReceipt {
        var result = ParsedReceipt()
        result.rawText = text
        let normalized = TextNormalizer.normalize(text)

        // 1. 金额
        result.amountCents = extractAmount(from: text)
        if let cents = result.amountCents {
            result.notes.append("语音金额：\(MoneyFormatter.string(cents: cents))")
        } else {
            result.notes.append("语音里没听出金额")
        }

        // 2. 收支
        let incomeHit = incomeVerbs.contains { normalized.contains(TextNormalizer.normalize($0)) }
        let expenseHit = expenseVerbs.contains { normalized.contains(TextNormalizer.normalize($0)) }
        if incomeHit && !expenseHit {
            result.kind = .income
            result.kindConfidence = 0.9
        } else if expenseHit {
            result.kind = .expense
            result.kindConfidence = 0.88
        } else {
            result.kind = .expense
            result.kindConfidence = 0.6
        }

        // 3. 时间
        let dateResult = parseRelativeDate(text: text, now: now)
        result.occurredAt = dateResult.date
        result.didParseDate = dateResult.parsed

        // 4. 商户
        result.merchant = extractMerchant(from: text, normalized: normalized)

        // 5. 商品（剩余文字）
        result.item = extractItem(from: text)

        // 6. 平台
        result.platform = detectPlatform(normalized)

        // 7. 置信度
        var score = 0.4
        if result.amountCents != nil { score += 0.35 }
        if !result.merchant.isEmpty { score += 0.1 }
        if result.kindConfidence >= 0.85 { score += 0.1 }
        result.confidence = min(score, 0.96)
        return result
    }

    // MARK: - 金额

    private static func extractAmount(from text: String) -> Int? {
        // 优先匹配带「元 / 块」的数字
        if let match = RegexHelper.firstMatch(#"(\d+(?:\.\d{1,2})?)\s*(?:元|块钱|块|圆)"#, in: text),
           let valueText = match.groups.first ?? nil,
           let cents = MoneyFormatter.cents(fromYuanText: valueText) {
            return cents
        }
        // 其次匹配带 ¥ 的数字
        if let match = RegexHelper.firstMatch(#"[¥￥]\s*(\d+(?:\.\d{1,2})?)"#, in: text),
           let valueText = match.groups.first ?? nil,
           let cents = MoneyFormatter.cents(fromYuanText: valueText) {
            return cents
        }
        // 兜底：取最后一个数字
        let all = RegexHelper.matches(#"\d+(?:\.\d{1,2})?"#, in: text)
        if let last = all.last,
           let cents = MoneyFormatter.cents(fromYuanText: last.value),
           cents > 0, cents < 100_000_000 {
            return cents
        }
        return nil
    }

    // MARK: - 相对时间

    private static func parseRelativeDate(text: String, now: Date) -> (date: Date, parsed: Bool) {
        let calendar = Calendar(identifier: .gregorian)
        var dayOffset = 0
        var parsed = false

        if text.contains("前天") {
            dayOffset = -2
            parsed = true
        } else if text.contains("昨天") || text.contains("昨晚") {
            dayOffset = -1
            parsed = true
        } else if text.contains("今天") || text.contains("今晚") || text.contains("今早") {
            dayOffset = 0
            parsed = true
        }

        var hour: Int?
        var minute = 0

        let period: [(String, Int)] = [
            ("凌晨", 3), ("早上", 8), ("早晨", 8), ("上午", 10),
            ("中午", 12), ("下午", 15), ("傍晚", 18), ("晚上", 20), ("夜里", 23)
        ]
        for (keyword, defaultHour) in period where text.contains(keyword) {
            hour = defaultHour
            parsed = true
            break
        }

        if let match = RegexHelper.firstMatch(#"(\d{1,2})[:：点](\d{1,2})?"#, in: text),
           let hourText = match.groups.first ?? nil,
           let parsedHour = Int(hourText), parsedHour < 24 {
            hour = parsedHour
            if match.groups.count > 1, let minuteText = match.groups[1], let parsedMinute = Int(minuteText) {
                minute = min(parsedMinute, 59)
            }
            parsed = true
        }

        if let explicitDate = RegexHelper.firstMatch(#"(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})日?"#, in: text),
           let yearText = explicitDate.groups.first ?? nil, let year = Int(yearText),
           let monthText = explicitDate.groups.count > 1 ? explicitDate.groups[1] : nil, let month = Int(monthText),
           let dayText = explicitDate.groups.count > 2 ? explicitDate.groups[2] : nil, let day = Int(dayText) {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            comps.hour = hour ?? 12
            comps.minute = minute
            if let date = calendar.date(from: comps) {
                return (date, true)
            }
        }

        let base = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        if let hour {
            var comps = calendar.dateComponents([.year, .month, .day], from: base)
            comps.hour = hour
            comps.minute = minute
            return (calendar.date(from: comps) ?? now, true)
        }
        return (base, parsed)
    }

    // MARK: - 商户

    private static func extractMerchant(from text: String, normalized: String) -> String {
        // 「在星巴克买了杯咖啡」
        if let match = RegexHelper.firstMatch(#"在(.{2,14}?)(?:买|吃|喝|花|消费|付|加油|充|交)"#, in: text),
           let merchant = match.groups.first ?? nil, !merchant.isEmpty {
            return merchant
        }
        // 「星巴克花了 28」
        if let match = RegexHelper.firstMatch(#"^(.{2,14}?)(?:花了|消费了|付了|买了|吃了|喝了)"#, in: text),
           let merchant = match.groups.first ?? nil, !merchant.isEmpty {
            return merchant
        }
        // 用词典识别品牌
        if let brand = BrandLexicon.category(for: text) {
            _ = brand
            // 从原文中截取命中词附近内容
            for entry in BrandLexicon.entries {
                for keyword in entry.keywords where text.contains(keyword) {
                    return keyword
                }
            }
        }
        return ""
    }

    private static func extractItem(from text: String) -> String {
        // 「买了杯咖啡」→ 咖啡
        if let match = RegexHelper.firstMatch(#"(?:买|吃|喝|充|交)了?(.{1,10}?)(?:\s*[，,。]|\s*花|$)"#, in: text),
           let item = match.groups.first ?? nil {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 1, trimmed.count <= 12 {
                return trimmed
            }
        }
        return ""
    }

    private static func detectPlatform(_ normalized: String) -> PaymentPlatform {
        if normalized.contains("微信") { return .wechat }
        if normalized.contains("支付宝") || normalized.contains("花呗") { return .alipay }
        if normalized.contains("银行卡") || normalized.contains("信用卡") { return .bankCard }
        if normalized.contains("现金") { return .cash }
        return .other
    }
}
