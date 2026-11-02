//
//  ReceiptParserTests.swift
//  轻点记账 · 单元测试
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
}
