//
//  ImportServiceTests.swift
//  简记
//
//  账单导入的回归测试：微信 xlsx / CSV 的真实结构都覆盖到。
//  背景：微信导出的账单里「交易类型」和「收/支」两列并存，时间还是 Excel 序列号，
//  这里把踩过的坑全部固化成用例。
//

import XCTest
@testable import QingDianJiZhang

/// ObjC 运行时里有个 `Category`（objc_category），会和我们的 SwiftData 模型撞名，
/// 这里显式指向 App 里的那个类型。
private typealias Category = QingDianJiZhang.Category

/// 账单文件导入（xlsx / CSV）的回归测试。
/// 注意：LogicTests.swift 里已经有一个基础的 `ImportServiceTests`，这里换名字避免重复声明。
final class BillImportTests: XCTestCase {

    /// 测试用分类：与 App 首次启动时写入的系统分类一致
    private var categories: [Category] {
        SystemCategories.all.enumerated().map { index, def in
            Category(
                name: def.name,
                symbolName: def.symbol,
                colorHex: def.color,
                scope: def.scope,
                isSystem: true,
                sortIndex: index
            )
        }
    }

    private func importCSV(_ text: String) throws -> ImportService.Result {
        let data = Data(text.utf8)
        return try ImportService.drafts(from: data, fileName: "账单.csv", categories: categories)
    }

    // MARK: - 样本

    /// 结构与微信导出的账单一致：前面 3 行说明，第 4 行表头，
    /// 「交易类型」和「收/支」同时存在，中性交易写「/」
    private let wechatCSV = """
    微信支付账单明细
    微信昵称：[测试]
    ----------------------微信支付账单明细列表--------------------
    交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
    2026-08-02 10:17:00,商户消费,依纯便利店,/,支出,¥1.00,零钱通,支付成功,4500000579202610309265247099,1011343602151793354614010800890,/
    2026-08-02 11:20:00,转账,味佳美餐厅,转账备注:微信转账,支出,9.00,零钱,对方已收钱,53010003393032202610310720440475,1000050001202610310635403867414,/
    2026-08-03 09:00:00,二维码收款,张三,收款方备注:二维码收款,收入,30.00,零钱,已收钱,53110002120225202608031234982793,10001073012026080301235186163612,/
    2026-08-03 10:00:00,转入零钱通-来自浦发银行(6354),/,/,/,500.00,浦发银行储蓄卡(6354),支付成功,4500000452202610128293109052,18000079832610120182042865417895,/
    2026-08-04 12:00:00,商户消费,某某商店,/,支出,30.00,零钱,已全额退款,4500000268202608032089859622,20260803191950U78038516450543165,/
    2026-08-04 12:05:00,某某商店-退款,某某商店,某某商店,收入,30.00,零钱,已全额退款,50102109062026103028556082469,,/
    2026-08-05 08:00:00,商户消费,美团平台商户,美团外卖,支出,30.90,零钱,交易关闭,4500000268202608032089859623,20260803191950U78038516450543166,/
    """

    // MARK: - 用例

    /// 「收/支」列不能被「交易类型」抢走：微信账单里两列并存，
    /// 旧逻辑按包含匹配，「交易类型」靠「类型」二字赢下收支列，收入全被记成支出。
    func testIncomeColumnWinsOverTransactionType() throws {
        let result = try importCSV(wechatCSV)
        let income = result.drafts.filter { $0.kind == .income }
        XCTAssertEqual(income.count, 2, "第 3 行「收入」和第 6 行退款都必须是收入")
        XCTAssertEqual(result.drafts.count, 5, "7 行数据里，1 笔中性 + 1 笔交易关闭要排除")
        XCTAssertEqual(result.detectedFormat, "微信支付账单")
        XCTAssertTrue(result.drafts.allSatisfy { $0.platform == .wechat })
    }

    /// 中性交易（充值 / 提现 / 零钱通存取）的「收/支」写的是「/」，不能当支出
    func testNeutralTransactionIsSkipped() throws {
        let result = try importCSV(wechatCSV)
        XCTAssertFalse(result.drafts.contains { $0.amountCents == 50000 }, "500 元的零钱通转入不能入账")
        XCTAssertTrue(
            result.warnings.contains { $0.contains("中性交易") },
            "应提示跳过了中性交易，实际：\(result.warnings)"
        )
    }

    /// 退款的两边都要保留：原支出行 + 退款收入行，净额才正确
    func testRefundRowsAreKept() throws {
        let result = try importCSV(wechatCSV)
        let refundExpense = result.drafts.contains { $0.kind == .expense && $0.amountCents == 3000
            && $0.merchant.contains("某某商店") }
        let refundIncome = result.drafts.contains { $0.kind == .income && $0.amountCents == 3000
            && $0.merchant.contains("某某商店") }
        XCTAssertTrue(refundExpense, "原支出行要保留，否则净额会多算一笔收入")
        XCTAssertTrue(refundIncome, "退款收入行要保留，否则钱回来了却没记")
    }

    /// 交易关闭 / 支付失败的行不入账
    func testClosedTransactionIsSkipped() throws {
        let result = try importCSV(wechatCSV)
        XCTAssertFalse(result.drafts.contains { $0.amountCents == 3090 }, "交易关闭的美团订单不该入账")
        XCTAssertEqual(result.skippedRows, 1)
    }

    /// 时间要按 CSV 里的原值解析，不能全变成「现在」
    func testDateParsedFromText() throws {
        let result = try importCSV(wechatCSV)
        guard let first = result.drafts.first else { return XCTFail("没有解析出账单") }
        let comps = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute], from: first.occurredAt
        )
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 8)
        XCTAssertEqual(comps.day, 2)
        XCTAssertEqual(comps.hour, 10)
        XCTAssertEqual(comps.minute, 17)
    }

    /// 微信导出的 xlsx 把时间存成 Excel 序列号，必须能换算：
    /// 46326.778402777774 → 2026-10-31 18:40:54
    func testExcelSerialDate() {
        guard let date = ImportService.parseDate("46326.778402777774") else {
            return XCTFail("Excel 序列号没解析出来")
        }
        let comps = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 10)
        XCTAssertEqual(comps.day, 31)
        XCTAssertEqual(comps.hour, 18)
        XCTAssertEqual(comps.minute, 40)
        XCTAssertEqual(comps.second, 54)
    }

    /// 普通数字不能被当成日期（避免把乱列的数字读成 1900 年）
    func testSmallNumbersAreNotDates() {
        XCTAssertNil(ImportService.parseDate("5"))
        XCTAssertNil(ImportService.parseDate("20261031"))
        XCTAssertNil(ImportService.parseDate(""))
    }

    /// 带 BOM 的 CSV（Excel / 记事本另存为）也要能认表头
    func testBOMDoesNotBreakHeader() throws {
        let data = Data(("\u{FEFF}" + wechatCSV).utf8)
        let result = try ImportService.drafts(from: data, fileName: "账单.csv", categories: categories)
        XCTAssertEqual(result.drafts.count, 5, "带 BOM 时表头识别失败，实际：\(result.warnings)")
    }

    /// 导出文件里的占位符「/」不是真实内容
    func testPlaceholderSlashIsCleared() throws {
        let result = try importCSV(wechatCSV)
        guard let first = result.drafts.first else { return XCTFail() }
        XCTAssertEqual(first.note, "", "备注是「/」时应留空")
        XCTAssertEqual(first.item, "", "商品是「/」时应留空")
    }

    /// 个人昵称里的问候语不是商户，「/」也不能变成商户名
    func testPayeeNameAndSlashMerchant() throws {
        let result = try importCSV(wechatCSV)
        let incoming = result.drafts.first { $0.kind == .income && $0.amountCents == 3000
            && $0.merchant == "张三" }
        XCTAssertNotNil(incoming, "收款人应识别为「张三」")
        XCTAssertFalse(result.drafts.contains { $0.merchant == "/" })
    }
}
