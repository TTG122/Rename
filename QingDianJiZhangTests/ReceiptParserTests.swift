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

    // MARK: - 回归：真机截图（1.1.0 修复）

    /// 相册预览里一屏两笔：金额被取第一笔，方向却被第二笔的「支付成功」带跑
    private let twoReceiptsText = """
    10:17
    转账成功
    ¥7300.00
    10:40
    支付成功
    ¥6251.00
    """

    func testTwoReceiptsTakeTopmostOnly() {
        let result = ReceiptParser.parse(text: twoReceiptsText)
        XCTAssertEqual(result.amountCents, 730000, "只应取最上面那一笔 7300.00")
        XCTAssertEqual(result.kind, .expense, "方向应来自「转账成功」，不是下面那张的「支付成功」")
        XCTAssertTrue(result.notes.contains { $0.contains("2 笔") }, "应在识别详情里提示画面有两笔")
    }

    /// 微信「你已收款」到账页：收入 1000，时间取收款时间而不是转账时间
    private let incomingText = """
    你已收款，资金已存入零钱
    ¥1000.00
    零钱余额
    转账时间 2026年07月29日 09:17:55
    收款时间 2026年07月29日 10:28:27
    """

    func testIncomingTransfer() {
        let result = ReceiptParser.parse(text: incomingText)
        XCTAssertEqual(result.kind, .income, "「你已收款」必须是收入")
        XCTAssertEqual(result.amountCents, 100000)
        XCTAssertEqual(result.platform, .wechat, "零钱是微信零钱")
        XCTAssertEqual(result.merchant, "", "「你已收款，资金已存入零钱」是提示语，不是商户")
    }

    func testIncomingTransferUsesReceiveTime() {
        let result = ReceiptParser.parse(text: incomingText)
        XCTAssertTrue(result.didParseDate)
        let comps = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: result.occurredAt
        )
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 7)
        XCTAssertEqual(comps.day, 29)
        XCTAssertEqual(comps.hour, 10, "应取「收款时间 10:28」，不是「转账时间 09:17」")
        XCTAssertEqual(comps.minute, 28)
    }

    /// 药店：商户取「意民平价大药房」，不能被「完成」按钮带偏
    func testPharmacyPayment() {
        let result = ReceiptParser.parse(text: """
        支付成功
        意民平价大药房
        ¥96.00
        完成
        """)
        XCTAssertEqual(result.amountCents, 9600)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertTrue(result.merchant.contains("意民"), "实际：\(result.merchant)")
    }

    // MARK: - 回归：真机截图（1.1.2 修复）

    /// 支付宝：页面底部广告「获得最高5元碰一下支付红包」不能盖过主金额 24.00
    func testAlipayPromoTextIsNotAmount() {
        let result = ReceiptParser.parse(text: """
        12:51
        支付成功
        回首页
        ¥24.00
        *锶锶  ¥24.00
        付款方式 支付宝小荷包(小红车)
        支付宝积分+2 体验金+18 一键领
        支付有礼
        获得最高5元碰一下支付红包
        立即领
        丸美 小红笔眼霜4.0
        到手超4支眼霜量 再送生日周边
        立即购买
        完成
        """)
        XCTAssertEqual(result.amountCents, 2400, "「5元」是广告文案，不是本笔金额")
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.merchant, "", "打码昵称与广告行都不是商户")
    }

    /// 微信扫码付款给个人：商户应是收款人昵称，不是「收款方备注 二维码收款」
    func testPersonalQRPaymentUsesPayeeName() {
        let result = ReceiptParser.parse(text: """
        22:28
        账单
        扫二维码付款-给みや、
        -130.00
        当前状态 支付成功
        收款方备注 二维码收款
        支付方式 零钱通
        转账时间 2026年8月12日 22:11:14
        转账单号
        10001073012026081200412311519112
        """)
        XCTAssertEqual(result.amountCents, 13000)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.merchant, "みや", "收款人是个人昵称，实际：\(result.merchant)")
    }

    /// 淘宝账单：字段名是「商户简称」，不能把「简称」两个字带进商户名
    func testMerchantShortNameLabel() {
        let result = ReceiptParser.parse(text: """
        21:10
        淘宝平台商户
        -705.00
        当前状态 支付成功
        支付时间 2025年10月2日 18:23:50
        商户简称 淘宝平台商户
        收单机构 财付通支付科技有限公司
        支付方式 工商银行储蓄卡(0092)
        交易单号 4440302262202510028845408022
        """)
        XCTAssertEqual(result.amountCents, 70500)
        XCTAssertEqual(result.merchant, "淘宝平台商户", "实际：\(result.merchant)")
    }

    /// 转账付款页底部有「收款账户」「预计10秒内到账」，不能据此判成收入
    func testOutgoingTransferIsExpense() {
        let result = ReceiptParser.parse(text: """
        完成
        转账成功
        预计10秒内到账，实际时间取决于收款银行。
        转账金额 500,000.00元
        收款账户 苏州悦贵房地产开发有限公司
        """)
        XCTAssertEqual(result.kind, .expense, "付款方的「转账成功」是支出")
        XCTAssertEqual(result.amountCents, 50000000, "50 万带千分位也要能解析")
        XCTAssertEqual(result.merchant, "苏州悦贵房地产开发有限公司", "实际：\(result.merchant)")
    }

    /// 抖音电商账单：大字号实付 16,434.42 要压过「订单金额 16435.00」
    func testDouyinOrderAmountDoesNotWin() {
        let result = ReceiptParser.parse(text: """
        16:39
        账单详情
        抖音电商商家
        -16,434.42
        交易成功
        订单金额 16435.00
        花呗立减 -0.58
        支付时间 2026-07-05 16:30:23
        付款方式 余额宝 11,434.42
        花呗 5,000.00
        组合支付
        收款方全称 上海格物致品网络科技有限公司
        """)
        XCTAssertEqual(result.amountCents, 1643442, "订单金额 16435.00 不是实付")
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.merchant, "上海格物致品网络科技有限公司", "实际：\(result.merchant)")
    }

    /// 抖音支付：还款金额 500 不能盖过实付 487.20；「+6抖音支付积分」不能当收入
    func testRepaymentAmountDoesNotWin() {
        let result = ReceiptParser.parse(text: """
        08:17
        支付成功
        已提交银行处理
        ¥487.20
        立减优惠 -¥12.80
        还款进度 银行处理中，预计今天到账
        还款金额 ¥500.00
        更多信息
        抖音支付 笔笔返现10%
        最高1.8元生活缴费券
        +6抖音支付积分
        完成
        """)
        XCTAssertEqual(result.amountCents, 48720, "实付 487.20，不是还款金额 500.00")
        XCTAssertEqual(result.kind, .expense, "「+6抖音支付积分」不是带符号金额")
        XCTAssertEqual(result.merchant, "", "返现、领券等营销行不是商户")
    }

    /// 深圳通：订单 7.00 / 立减 0.01，实付是 6.99
    func testShenzhenTongFare() {
        let result = ReceiptParser.parse(text: """
        账单详情
        深圳通
        -6.99
        自动付款成功
        订单金额 ¥7.00
        抖音支付立减 ¥0.01
        付款方式 抖音支付(工行信用卡4735)
        商品说明 抖音乘车码乘车-地铁2026-07-27 16:17:24
        支付时间 2026-07-27 17:27:24
        商户全称 深圳市深圳通有限公司
        """)
        XCTAssertEqual(result.amountCents, 699, "订单金额 7.00 与立减 0.01 都不是实付")
        XCTAssertEqual(result.merchant, "深圳市深圳通有限公司", "实际：\(result.merchant)")
    }

    /// 「实付」和金额分两行写时，金额要继承标签的权重
    func testLabelAndAmountOnSeparateLines() {
        let result = ReceiptParser.parse(text: """
        支付成功
        肯德基
        订单金额
        ¥45.00
        优惠
        -¥9.00
        实付
        ¥36.00
        """)
        XCTAssertEqual(result.amountCents, 3600, "实付是 36.00，不是订单金额 45.00")
    }

    /// 银行短信：一行里同时有消费额和余额，不能把整行当余额，也不能当单号
    func testBankSMSWithBalanceOnSameLine() {
        let result = ReceiptParser.parse(
            text: "您尾号1234的储蓄卡10月23日14:22消费人民币58.00元，余额1,204.20元。【招商银行】"
        )
        XCTAssertEqual(result.amountCents, 5800, "消费 58.00，不是余额 1,204.20")
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.platform, .bankCard)
    }

    // MARK: - 回归：真机截图（1.1.4）

    /// 微信账单页的负号是排版符号 U+2212，不是键盘上的 `-`。
    /// 旧逻辑认不出「−50.00」，金额退化到从「储蓄卡(6354)」取卡号尾号。
    func testTypographicMinusIsUnderstood() {
        let text = """
        14:16
        账单
        扫二维码付款-给文文
        \u{2212}50.00
        当前状态 支付成功
        收款方备注 二维码收款
        支付方式 浦发银行储蓄卡(6354)
        转账时间 2026年10月26日 11:47:22
        转账单号 10001073012026102601523144247524
        账单服务
        收款方服务
        收款方名片
        本服务由财付通提供
        """
        let result = ReceiptParser.parse(text: text)
        XCTAssertEqual(result.amountCents, 5000, "「−50.00」必须识别成 50 元")
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.merchant, "文文", "商户应是收款人，不是「服务」，实际：\(result.merchant)")
        XCTAssertEqual(result.platform, .wechat, "财付通即微信支付")
    }

    /// 卡号尾号不能当金额：金额识别失败时宁可留空，也不要记成 6354 元
    func testCardTailIsNotAmount() {
        let result = ReceiptParser.parse(text: """
        支付成功
        某商户
        支付方式 招商银行储蓄卡(6354)
        完成
        """)
        XCTAssertNil(result.amountCents, "储蓄卡(6354) 里的是卡尾号，不是金额")
    }

    /// 全角数字 / 全角负号也要能解析
    func testFullWidthAmount() {
        let result = ReceiptParser.parse(text: """
        支付成功
        便利店
        －５０．００
        微信支付
        """)
        XCTAssertEqual(result.amountCents, 5000)
    }

    /// 状态栏的电量/信号会被 OCR 当正文读出来，而且因为在页面顶部还能拿到「顶部加分」，
    /// 权重正好压过真正的金额。用户实测：50 元被记成 4 元，就是状态栏那个「4」干的。
    func testStatusBarNumbersAreIgnored() {
        let result = ReceiptParser.parse(text: """
        14:16
        4
        账单
        扫二维码付款-给文文
        -50.00
        当前状态 支付成功
        支付方式 浦发银行储蓄卡（6354）
        收款方服务
        """)
        XCTAssertEqual(result.amountCents, 5000, "状态栏的 4 不能当金额")
        XCTAssertEqual(result.merchant, "文文")
        XCTAssertNotEqual(result.item, "-50.00", "金额那一行不该被塞进「内容」")
    }

    /// 纯整数、不带小数/符号/元的行不是金额
    func testBareIntegerIsNotAmount() {
        let result = ReceiptParser.parse(text: "支付成功\n72\n完成")
        XCTAssertNil(result.amountCents)
    }
}
