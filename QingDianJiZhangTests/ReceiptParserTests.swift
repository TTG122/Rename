//
//  ReceiptParserTests.swift
//  简记 · 单元测试
//

import XCTest
@testable import QingDianJiZhang

final class ReceiptParserTests: XCTestCase {

    // 微信支付成功页的典型结构
    private let wechatText = """
    支付成功
    星巴克(国贸店)
    ¥36.00
    微信支付
    招商银行储蓄卡(1234)
    2026-11-02 09:12:33
    商户单号 4200002026110200123
    """

    func testWechatExpense() {
        let result = ReceiptParser.parse(text: wechatText)

        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.amountCents, 3600)
        XCTAssertEqual(result.platform, .wechat)
        XCTAssertTrue(result.merchant.contains("星巴克"), "商户应识别为星巴克，实际：\(result.merchant)")
        XCTAssertFalse(result.orderNumber.isEmpty)
        XCTAssertGreaterThan(result.confidence, 0.6)
    }

    func testDiscountShouldNotBeUsedAsAmount() {
        // 这是最容易出错的地方：三个金额同时出现
        let text = """
        支付成功
        麦当劳
        订单金额 ¥45.00
        优惠 -¥9.00
        实付金额 ¥36.00
        支付宝
        """
        let result = ReceiptParser.parse(text: text)
        XCTAssertEqual(result.amountCents, 3600, "应该取实付金额，而不是订单金额或优惠金额")
        XCTAssertEqual(result.platform, .alipay)
    }

    func testIncomeRefund() {
        let text = """
        退款成功
        淘宝
        退款金额 ¥128.00
        已退回到支付宝余额
        """
        let result = ReceiptParser.parse(text: text)
        XCTAssertEqual(result.kind, .income)
        XCTAssertEqual(result.amountCents, 12800)
        XCTAssertEqual(result.platform, .alipay)
    }

    func testOrderNumberIsNotTreatedAsAmount() {
        let text = """
        支付成功
        滴滴出行
        交易单号 2026110222001234567890
        ¥23.50
        微信支付
        """
        let result = ReceiptParser.parse(text: text)
        XCTAssertEqual(result.amountCents, 2350)
    }

    func testDateParsing() {
        let result = ReceiptParser.parse(text: wechatText)
        XCTAssertTrue(result.didParseDate)
        let comps = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour],
            from: result.occurredAt
        )
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 11)
        XCTAssertEqual(comps.day, 2)
        XCTAssertEqual(comps.hour, 9)
    }

    func testUnknownKindIsUncertain() {
        let result = ReceiptParser.parse(text: "星巴克 36.00")
        XCTAssertLessThan(result.kindConfidence, 0.7, "没有方向关键词时不应该给出高置信度")
    }

    // MARK: - 回归：微信「零钱明细」退款页

    /// 真实截图：退款 +4.00，交易单号 30 位，余额 ¥4.20。
    /// 旧逻辑把单号尾数 9895 当成金额，并判成支出。
    private let walletRefundText = """
    零钱明细
    退款
    +4.00
    类型
    退款
    时间
    2026年10月31日 18:40:54
    交易单号
    142745160226022110097341626253429895
    余额
    ¥4.20
    备注
    京津冀互联互通卡 充值
    """

    func testWalletRefundAmountComesFromSignedValue() {
        let result = ReceiptParser.parse(text: walletRefundText)
        XCTAssertEqual(result.amountCents, 400, "应取 +4.00，而不是交易单号尾数 9895 或余额 4.20")
    }

    func testWalletRefundIsIncome() {
        let result = ReceiptParser.parse(text: walletRefundText)
        XCTAssertEqual(result.kind, .income, "退款带 + 号，必须记为收入")
        XCTAssertGreaterThan(result.kindConfidence, 0.7)
    }

    func testWalletRefundMerchantComesFromNote() {
        let result = ReceiptParser.parse(text: walletRefundText)
        XCTAssertTrue(result.merchant.contains("京津冀"), "商户应取备注内容，实际：\(result.merchant)")
        XCTAssertFalse(result.merchant.contains("充值"), "备注里的动作词应被剔除，实际：\(result.merchant)")
    }

    /// 余额的数值常常单独占一行，不能被误当成金额
    func testBalanceLineIsNotAmount() {
        let text = """
        零钱明细
        支出
        -12.80
        余额
        ¥1,204.20
        """
        let result = ReceiptParser.parse(text: text)
        XCTAssertEqual(result.amountCents, 1280, "应取 -12.80，而不是余额 1204.20")
        XCTAssertEqual(result.kind, .expense)
    }

    /// 单号被 OCR 拆成若干短数字时，也不能取其中一段当金额
    func testSplitOrderNumberIsNotAmount() {
        let text = """
        零钱明细
        支出
        -3.50
        交易单号
        1427 4516 0226 0221 1009 7341 6262 5342 9895
        """
        let result = ReceiptParser.parse(text: text)
        XCTAssertEqual(result.amountCents, 350, "拆分后的单号片段不能成为金额")
    }
}
