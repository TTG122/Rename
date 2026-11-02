//
//  LogicTests.swift
//  简记 · 单元测试（查重 / 语音 / 导入 / Excel / 月报）
//

import XCTest
@testable import QingDianJiZhang

// MARK: - 查重

final class DuplicateDetectorTests: XCTestCase {

    private func makeExisting(
        amount: Int = 3600,
        merchant: String = "星巴克",
        orderNumber: String = "",
        imageHash: String = "",
        minutesAgo: Double = 0
    ) -> Transaction {
        Transaction(
            kind: .expense,
            amountCents: amount,
            merchant: merchant,
            occurredAt: Date(timeIntervalSinceNow: -minutesAgo * 60),
            orderNumber: orderNumber,
            imageHash: imageHash
        )
    }

    private func makeDraft(
        amount: Int = 3600,
        merchant: String = "星巴克",
        orderNumber: String = "",
        imageHash: String = "",
        minutesAgo: Double = 0
    ) -> TransactionDraft {
        var draft = TransactionDraft()
        draft.amountCents = amount
        draft.merchant = merchant
        draft.orderNumber = orderNumber
        draft.imageHash = imageHash
        draft.occurredAt = Date(timeIntervalSinceNow: -minutesAgo * 60)
        return draft
    }

    func testSameOrderNumberIsDuplicate() {
        let existing = makeExisting(orderNumber: "4200001234", minutesAgo: 300)
        var draft = makeDraft(orderNumber: "4200001234", minutesAgo: 0)
        draft.merchant = "完全不同的商户"
        draft.amountCents = 999

        let verdict = DuplicateDetector.check(draft: draft, against: [existing])
        XCTAssertTrue(verdict.isSuspected)
    }

    func testSameAmountMerchantAndTimeIsDuplicate() {
        let existing = makeExisting(minutesAgo: 2)
        let draft = makeDraft(minutesAgo: 0)
        XCTAssertTrue(DuplicateDetector.check(draft: draft, against: [existing]).isSuspected)
    }

    func testDifferentAmountIsNotDuplicate() {
        let existing = makeExisting(amount: 3600, minutesAgo: 1)
        let draft = makeDraft(amount: 3700, minutesAgo: 0)
        XCTAssertFalse(DuplicateDetector.check(draft: draft, against: [existing]).isSuspected)
    }

    func testFarApartInTimeIsNotDuplicate() {
        let existing = makeExisting(minutesAgo: 60 * 24 * 3)
        let draft = makeDraft(minutesAgo: 0)
        // 3 天前同一商户同金额，不算重复
        XCTAssertFalse(DuplicateDetector.check(draft: draft, against: [existing]).isSuspected)
    }

    func testSameImageHashIsDuplicate() {
        let existing = makeExisting(amount: 100, merchant: "A", imageHash: "abcdef", minutesAgo: 5000)
        let draft = makeDraft(amount: 200, merchant: "B", imageHash: "abcdef", minutesAgo: 0)
        XCTAssertTrue(DuplicateDetector.check(draft: draft, against: [existing]).isSuspected)
    }
}

// MARK: - 语音

final class VoiceParserTests: XCTestCase {

    func testLunchSentence() {
        let result = VoiceCommandParser.parse(text: "今天中午吃饭花了28元")
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.amountCents, 2800)

        let hour = Calendar.current.component(.hour, from: result.occurredAt)
        XCTAssertEqual(hour, 12)
    }

    func testIncomeSentence() {
        let result = VoiceCommandParser.parse(text: "收到工资12000元")
        XCTAssertEqual(result.kind, .income)
        XCTAssertEqual(result.amountCents, 1_200_000)
    }

    func testMerchantInSentence() {
        let result = VoiceCommandParser.parse(text: "在星巴克买咖啡花了36元")
        XCTAssertEqual(result.amountCents, 3600)
        XCTAssertTrue(result.merchant.contains("星巴克"))
    }

    func testYesterday() {
        let result = VoiceCommandParser.parse(text: "昨天打车38块")
        let calendar = Calendar.current
        XCTAssertTrue(calendar.isDateInYesterday(result.occurredAt)
                      || calendar.dateComponents([.day], from: result.occurredAt, to: .now).day == 1)
        XCTAssertEqual(result.amountCents, 3800)
    }

    func testNoAmount() {
        let result = VoiceCommandParser.parse(text: "随便说点什么")
        XCTAssertNil(result.amountCents)
    }
}

// MARK: - CSV / 导入

final class ImportServiceTests: XCTestCase {

    func testCSVParsingWithQuotes() {
        let csv = """
        日期,商户,金额,备注
        2026-11-01,"星巴克,国贸店",36.00,"带""引号""的备注"
        """
        let rows = ImportService.parseCSV(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][1], "星巴克,国贸店")
        XCTAssertEqual(rows[1][3], "带\"引号\"的备注")
    }

    func testWechatLikeCSVImport() throws {
        let csv = """
        微信支付账单明细
        导出时间：2026-11-02
        ----------------------
        交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
        2026-11-01 12:31:00,商户消费,星巴克,拿铁,支出,¥36.00,招商银行储蓄卡(1234),支付成功,4200001,4200002,
        2026-11-01 18:02:00,商户消费,滴滴出行,快车,支出,¥23.50,零钱,支付成功,4200003,4200004,
        2026-11-02 09:00:00,转账,公司,工资,收入,¥12000.00,零钱,已存入零钱,4200005,,
        """
        let data = Data(csv.utf8)
        let categories = SystemCategories.all.map {
            Category(name: $0.name, symbolName: $0.symbol, colorHex: $0.color, scope: $0.scope, isSystem: true)
        }
        let result = try ImportService.drafts(from: data, fileName: "账单.csv", categories: categories)

        XCTAssertEqual(result.drafts.count, 3)
        XCTAssertEqual(result.drafts[0].amountCents, 3600)
        XCTAssertEqual(result.drafts[0].categoryName, "吃饭")
        XCTAssertEqual(result.drafts[2].kind, .income)
    }

    func testDateFormatParsing() {
        XCTAssertNotNil(ImportService.parseDate("2026-11-02 09:12:33"))
        XCTAssertNotNil(ImportService.parseDate("2026/11/02 09:12"))
        XCTAssertNotNil(ImportService.parseDate("2026年11月2日"))
        XCTAssertNil(ImportService.parseDate("不是日期"))
    }
}

// MARK: - Excel 读写

final class XLSXTests: XCTestCase {

    func testWriteThenReadRoundTrip() throws {
        let rows: [[String]] = [
            ["日期", "商户", "金额"],
            ["2026-11-01", "星巴克 & 咖啡", "36.00"],
            ["2026-11-02", "中石化", "300.50"]
        ]
        let data = XLSXWriter.make(sheetName: "账单", rows: rows, numericColumns: [2])
        XCTAssertGreaterThan(data.count, 100)

        let parsed = try XLSXReader.rows(from: data)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0][0], "日期")
        XCTAssertEqual(parsed[1][1], "星巴克 & 咖啡")
        XCTAssertEqual(parsed[2][2], "300.5")
    }

    func testColumnLetter() {
        XCTAssertEqual(XLSXWriter.columnLetter(0), "A")
        XCTAssertEqual(XLSXWriter.columnLetter(25), "Z")
        XCTAssertEqual(XLSXWriter.columnLetter(26), "AA")
    }

    func testCRC32() {
        // "123456789" 的标准 CRC32
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
    }
}

// MARK: - 月报

final class MonthlyReportTests: XCTestCase {

    private func makeCategories() -> [Category] {
        SystemCategories.all.map {
            Category(name: $0.name, symbolName: $0.symbol, colorHex: $0.color, scope: $0.scope, isSystem: true)
        }
    }

    private func makeTransaction(daysAgo: Int, amount: Int, category: String, merchant: String, kind: TransactionKind = .expense) -> Transaction {
        Transaction(
            kind: kind,
            amountCents: amount,
            merchant: merchant,
            categoryName: category,
            occurredAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        )
    }

    func testTotalsAndBreakdown() {
        let transactions = [
            makeTransaction(daysAgo: 1, amount: 3600, category: "吃饭", merchant: "星巴克"),
            makeTransaction(daysAgo: 2, amount: 6400, category: "吃饭", merchant: "海底捞"),
            makeTransaction(daysAgo: 3, amount: 30_000, category: "加油", merchant: "中石化"),
            makeTransaction(daysAgo: 4, amount: 1_200_000, category: "工资收入", merchant: "公司", kind: .income)
        ]

        let report = MonthlyReportBuilder.build(
            month: .now,
            transactions: transactions,
            categories: makeCategories(),
            budgets: [Budget(monthKey: "", amountCents: 500_000)]
        )

        XCTAssertEqual(report.totalExpenseCents, 40_000)
        XCTAssertEqual(report.totalIncomeCents, 1_200_000)
        XCTAssertEqual(report.balanceCents, 1_160_000)
        XCTAssertEqual(report.categoryBreakdown.first?.name, "加油")
        XCTAssertEqual(report.categoryBreakdown.first?.amountCents, 30_000)
        XCTAssertFalse(report.summaryText.isEmpty)
        XCTAssertFalse(report.suggestions.isEmpty)
    }

    func testEmptyMonth() {
        let report = MonthlyReportBuilder.build(
            month: .now,
            transactions: [],
            categories: makeCategories(),
            budgets: []
        )
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.totalExpenseCents, 0)
    }

    func testAnomalyDetection() {
        let transactions = [
            makeTransaction(daysAgo: 1, amount: 2000, category: "购物", merchant: "A"),
            makeTransaction(daysAgo: 2, amount: 2100, category: "购物", merchant: "B"),
            makeTransaction(daysAgo: 3, amount: 2200, category: "购物", merchant: "C"),
            makeTransaction(daysAgo: 4, amount: 900_00, category: "购物", merchant: "D")
        ]
        let report = MonthlyReportBuilder.build(
            month: .now,
            transactions: transactions,
            categories: makeCategories(),
            budgets: []
        )
        XCTAssertFalse(report.anomalies.isEmpty, "900 元相对 2000 元左右的均值应被标记为异常")
    }
}

// MARK: - 金额格式

final class MoneyFormatterTests: XCTestCase {

    func testCentsConversion() {
        XCTAssertEqual(MoneyFormatter.cents(fromYuanText: "36.00"), 3600)
        XCTAssertEqual(MoneyFormatter.cents(fromYuanText: "¥1,234.56"), 123_456)
        XCTAssertEqual(MoneyFormatter.cents(fromYuanText: "0.1"), 10)
        XCTAssertNil(MoneyFormatter.cents(fromYuanText: "abc"))
    }

    func testFormatting() {
        XCTAssertEqual(MoneyFormatter.string(cents: 3600), "36.00")
        XCTAssertEqual(MoneyFormatter.grouped(cents: 123_456), "1,234.56")
        XCTAssertEqual(MoneyFormatter.compact(cents: 1_200_000), "1.2万")
    }
}
