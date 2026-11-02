//
//  ImportService.swift
//  简记
//
//  批量导入：微信 / 支付宝 / 银行导出的 CSV，以及通用 CSV / Excel。
//  解析全部在本机完成，文件不会被上传。
//

import Foundation
import CoreFoundation

enum ImportError: LocalizedError {
    case unsupportedFile
    case emptyFile
    case headerNotFound
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: return "不支持这种文件格式，请用 CSV 或 xlsx"
        case .emptyFile: return "文件是空的"
        case .headerNotFound: return "没找到表头行，请确认导出的是账单明细"
        case .decodeFailed: return "文件编码无法识别，请另存为 UTF-8 或 CSV 后重试"
        }
    }
}

enum ImportService {

    struct Result {
        var drafts: [TransactionDraft] = []
        var warnings: [String] = []
        var detectedFormat: String = "通用账单"
        var skippedRows: Int = 0
        var duplicateInFile: Int = 0
    }

    // MARK: - 入口

    static func drafts(fromFileAt url: URL, categories: [Category]) throws -> Result {
        let data = try Data(contentsOf: url)
        return try drafts(from: data, fileName: url.lastPathComponent, categories: categories)
    }

    static func drafts(from data: Data, fileName: String, categories: [Category]) throws -> Result {
        guard !data.isEmpty else { throw ImportError.emptyFile }
        let lowerName = fileName.lowercased()
        let isZip = data.count > 4 && data[0] == 0x50 && data[1] == 0x4B

        if lowerName.hasSuffix(".xlsx") || isZip {
            let rows = try XLSXReader.rows(from: data)
            // xlsx 也要认格式：微信导出的账单平台、账户字段都依赖它
            return build(rows: rows, categories: categories, formatName: detectFormat(rows: rows))
        }

        guard let text = decodeText(data) else { throw ImportError.decodeFailed }
        let rows = parseCSV(text)
        return build(rows: rows, categories: categories, formatName: detectFormat(rows: rows))
    }

    // MARK: - 编码

    static func decodeText(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return stripBOM(utf8)
        }
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let gbk = String(data: data, encoding: gb18030) { return stripBOM(gbk) }
        return nil
    }

    /// Excel / 记事本另存的 CSV 常带 BOM，会让第一行第一个单元格多出一个不可见字符
    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    // MARK: - CSV 解析（RFC 4180）

    static func parseCSV(_ text: String) -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = 0

        while index < characters.count {
            let char = characters[index]

            if inQuotes {
                if char == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                field.append(char)
                index += 1
                continue
            }

            switch char {
            case "\"":
                inQuotes = true
                index += 1
            case ",":
                row.append(field)
                field = ""
                index += 1
            case "\r":
                index += 1
            case "\n":
                row.append(field)
                field = ""
                rows.append(row)
                row = []
                index += 1
            default:
                field.append(char)
                index += 1
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
    }

    // MARK: - 表头识别

    private struct ColumnMap {
        var dateTime: Int?
        var kind: Int?
        var amount: Int?
        var merchant: Int?
        var item: Int?
        var category: Int?
        var account: Int?
        var orderNumber: Int?
        var note: Int?
        var status: Int?
        var headerIndex: Int = 0
        var score: Int = 0
    }

    /// 没有「收/支」列时（银行流水、通用 CSV），用摘要 / 备注判断方向
    private static let incomeHints = [
        "工资", "薪资", "奖金", "收入", "转入", "收款", "退款", "退货", "利息", "分红", "报销", "红包"
    ]

    private static let keywordSets: [(keyPath: WritableKeyPath<ColumnMap, Int?>, keywords: [String])] = [
        (\.dateTime, ["交易时间", "交易日期", "付款时间", "记账时间", "日期", "时间"]),
        (\.kind, ["收/支", "收支类型", "收支", "类型", "借贷标志"]),
        (\.amount, ["金额(元)", "金额（元）", "交易金额", "发生额", "金额"]),
        (\.merchant, ["交易对方", "商户名称", "对方名称", "收款方", "交易对象", "商户", "对方"]),
        (\.item, ["商品说明", "商品名称", "商品", "摘要", "交易说明"]),
        (\.category, ["交易分类", "分类"]),
        (\.account, ["收/付款方式", "支付方式", "付款方式", "账户", "银行卡"]),
        (\.orderNumber, ["交易订单号", "交易单号", "商户单号", "订单号"]),
        (\.note, ["备注"]),
        (\.status, ["当前状态", "交易状态", "状态"])
    ]

    /// 表头里带这些字的列是「余额」类字段，不能当金额或支付账户用
    private static let balanceHeaderWords = ["余额", "额度"]

    private static func detectColumns(rows: [[String]]) -> ColumnMap? {
        var best: ColumnMap?

        for (rowIndex, row) in rows.prefix(40).enumerated() {
            var map = ColumnMap()
            map.headerIndex = rowIndex
            var score = 0
            let normalizedRow = row.map { TextNormalizer.normalize($0) }

            for entry in keywordSets {
                var matched: Int?

                // 第一轮：表头与关键词完全一致的列优先。
                // 微信账单里既有「交易类型」又有「收/支」，只按包含匹配的话
                // 「交易类型」会靠「类型」二字抢走收支列，导致 22 笔收入全被记成支出。
                for keyword in entry.keywords {
                    let key = TextNormalizer.normalize(keyword)
                    guard !key.isEmpty else { continue }
                    guard let column = normalizedRow.firstIndex(of: key) else { continue }
                    guard !isBalanceHeader(normalizedRow[column]) else { continue }
                    matched = column
                    break
                }

                // 第二轮：找不到完全一致的，再退化为包含匹配（兼容「金额(元)」「收/支金额」这类写法）
                if matched == nil {
                    for (columnIndex, cell) in normalizedRow.enumerated() {
                        guard !cell.isEmpty, !isBalanceHeader(cell) else { continue }
                        let hit = entry.keywords.contains { keyword in
                            let key = TextNormalizer.normalize(keyword)
                            return !key.isEmpty && cell.contains(key)
                        }
                        if hit {
                            matched = columnIndex
                            break
                        }
                    }
                }

                if let column = matched {
                    map[keyPath: entry.keyPath] = column
                    score += 1
                }
            }

            map.score = score
            if score >= 3 {
                if best == nil || score > best!.score {
                    best = map
                }
            }
        }
        return best
    }

    /// 「账户余额」「可用额度」这类列不是收支字段
    private static func isBalanceHeader(_ normalizedCell: String) -> Bool {
        balanceHeaderWords.contains { normalizedCell.contains(TextNormalizer.normalize($0)) }
    }

    private static func detectFormat(rows: [[String]]) -> String {
        let joined = rows.prefix(20).flatMap { $0 }.joined()
        if joined.contains("微信") { return "微信支付账单" }
        if joined.contains("支付宝") { return "支付宝账单" }
        if joined.contains("银行") { return "银行账单" }
        return "通用账单"
    }

    // MARK: - 组装草稿

    private static func build(rows: [[String]], categories: [Category], formatName: String) -> Result {
        var result = Result()
        result.detectedFormat = formatName

        guard let map = detectColumns(rows: rows) else {
            result.warnings.append(ImportError.headerNotFound.localizedDescription)
            return result
        }

        let dataRows = rows.dropFirst(map.headerIndex + 1)
        var seenKeys = Set<String>()
        var neutralSkipped = 0

        for row in dataRows {
            func value(_ keyPath: WritableKeyPath<ColumnMap, Int?>) -> String {
                guard let index = map[keyPath: keyPath], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let amountText = value(\.amount)
            guard let cents = MoneyFormatter.cents(fromYuanText: cleanAmount(amountText)), cents > 0 else {
                if !row.allSatisfy({ $0.isEmpty }) { result.skippedRows += 1 }
                continue
            }

            // 收支方向：微信账单用「收/支」列，中性交易（充值、提现、零钱通存取、
            // 信用卡还款）写的是「/」，这类不是真实收支，跳过但单独计数。
            // 注意这里不能先做占位符清洗，否则「/」会被抹成空字符串，判断就失效了。
            let kindText = value(\.kind)
            if kindText == "/" || kindText == "／" || kindText.contains("不计") {
                neutralSkipped += 1
                continue
            }
            var kind: TransactionKind = .expense
            if kindText.contains("收入") || kindText.contains("收款") || kindText.contains("转入")
                || kindText.contains("贷") {
                kind = .income
            } else if kindText.isEmpty, map.kind == nil {
                // 银行流水常常没有「收/支」列，只能从摘要 / 备注判断（「工资」「退款」）
                let hint = [value(\.item), value(\.note), value(\.merchant)].joined(separator: " ")
                if incomeHints.contains(where: { hint.contains($0) }) { kind = .income }
            }

            // 状态过滤：只跳过「钱没动」的行。
            // 「已退款」的行必须保留——微信把退款单独记一笔收入，原支出行也保留，
            // 两边都导入净额才正确；只留一边会把账做错。
            let status = cleanCell(value(\.status))
            let deadStatuses = ["交易关闭", "已关闭", "支付失败", "交易失败", "已撤销", "已取消", "已失效"]
            if deadStatuses.contains(where: { status.contains($0) }) {
                result.skippedRows += 1
                continue
            }

            let dateText = value(\.dateTime)
            let occurredAt = parseDate(dateText) ?? .now

            let merchant = cleanMerchant(cleanCell(value(\.merchant)))
            let item = cleanCell(value(\.item))
            let providedCategory = value(\.category)

            var categoryName = "其他"
            if !providedCategory.isEmpty,
               let matched = SeedData.category(named: providedCategory, in: categories) {
                categoryName = matched.name
            } else {
                let classification = RuleBasedClassifier().classify(
                    ClassificationInput(
                        merchant: merchant,
                        item: item,
                        rawText: row.joined(separator: " "),
                        kind: kind,
                        learnedRules: [:],
                        availableCategories: categories.map(\.name)
                    )
                )
                categoryName = classification.categoryName
            }

            var draft = TransactionDraft()
            draft.kind = kind
            draft.amountCents = cents
            draft.merchant = merchant
            draft.item = item
            draft.note = cleanCell(value(\.note))
            draft.categoryName = categoryName
            draft.categoryID = SeedData.category(named: categoryName, in: categories)?.id
            draft.occurredAt = occurredAt
            draft.platform = detectPlatform(row.joined(separator: " "), format: formatName)
            draft.account = cleanCell(value(\.account))
            draft.orderNumber = value(\.orderNumber)
            draft.source = .fileImport
            draft.confidence = 0.99
            draft.kindIsCertain = true

            // 文件内部去重：优先用交易单号（唯一），没有单号才退回「金额 + 商户 + 3 分钟窗口」
            let key: String
            if !draft.orderNumber.isEmpty {
                key = "no:\(draft.orderNumber)"
            } else {
                key = "\(cents)|\(TextNormalizer.normalize(merchant))|\(Int(occurredAt.timeIntervalSince1970 / 180))"
            }
            if seenKeys.contains(key) {
                result.duplicateInFile += 1
                continue
            }
            seenKeys.insert(key)

            result.drafts.append(draft)
        }

        if neutralSkipped > 0 {
            result.warnings.append("已跳过 \(neutralSkipped) 笔中性交易（充值 / 提现 / 零钱通存取等），不计入收支")
        }

        if result.drafts.isEmpty {
            result.warnings.append("没有解析出任何账单，请检查文件内容")
        }
        return result
    }

    // MARK: - 字段清洗

    /// 导出文件里的占位符（「/」「-」「—」）不是真实内容
    private static func cleanCell(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["/", "-", "—", "--", "无", "N/A", "n/a"].contains(trimmed) { return "" }
        return trimmed
    }

    private static func cleanAmount(_ text: String) -> String {
        text
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanMerchant(_ text: String) -> String {
        var value = text
        // 支付宝会在商户后加 "/" 分隔
        if let range = value.range(of: "/") {
            value = String(value[..<range.lowerBound])
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detectPlatform(_ text: String, format: String) -> PaymentPlatform {
        if format.contains("微信") { return .wechat }
        if format.contains("支付宝") { return .alipay }
        let parsed = ReceiptParser.parse(text: text)
        return parsed.platform
    }

    // MARK: - 日期

    private static let dateFormats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd HH:mm",
        "yyyy-MM-dd",
        "yyyy/MM/dd",
        "yyyy年M月d日 HH:mm:ss",
        "yyyy年M月d日 HH:mm",
        "yyyy年M月d日",
        "M/d/yyyy HH:mm:ss",
        "yyyyMMddHHmmss"
    ]

    static func parseDate(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Excel 把日期存成序列号，微信导出的 xlsx 账单时间列就是 46326.778402777774 这种
        if let serial = excelSerialDate(cleaned) { return serial }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return date
            }
        }
        // 去掉多余的秒 / 毫秒
        if let dotRange = cleaned.range(of: ".") {
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let date = formatter.date(from: String(cleaned[..<dotRange.lowerBound])) {
                return date
            }
        }
        return nil
    }

    /// Excel 日期序列号 → Date。
    /// 序列号以 1899-12-30 为第 0 天（该基准已包含 1900 年被误当成闰年的修正），
    /// 小数部分是当天的时间占比。下限 10000（约 1927 年）是为了避开「5」「20」这类
    /// 被错读成日期列的普通数字；上限覆盖到 9999 年。
    static func excelSerialDate(_ text: String) -> Date? {
        guard let serial = Double(text), serial.isFinite, serial >= 10_000, serial <= 2_958_465 else {
            return nil
        }
        let calendar = Calendar(identifier: .gregorian)
        let wholeDays = Int(serial)
        var comps = DateComponents()
        comps.year = 1899
        comps.month = 12
        comps.day = 30 + wholeDays
        guard let dayStart = calendar.date(from: comps) else { return nil }
        let fraction = serial - Double(wholeDays)
        return dayStart.addingTimeInterval((fraction * 86_400).rounded())
    }
}
