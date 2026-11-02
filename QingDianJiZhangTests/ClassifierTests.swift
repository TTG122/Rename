//
//  ClassifierTests.swift
//  简记 · 单元测试
//

import XCTest
@testable import QingDianJiZhang

final class ClassifierTests: XCTestCase {

    private let classifier = RuleBasedClassifier()

    private func classify(merchant: String, item: String = "", text: String = "", kind: TransactionKind = .expense, rules: [String: String] = [:]) -> ClassificationResult {
        classifier.classify(
            ClassificationInput(
                merchant: merchant,
                item: item,
                rawText: text,
                kind: kind,
                learnedRules: rules
            )
        )
    }

    func testFuelStation() {
        let result = classify(merchant: "中国石化杭州文一路加油站")
        XCTAssertEqual(result.categoryName, "加油")
    }

    func testRestaurant() {
        XCTAssertEqual(classify(merchant: "星巴克(国贸店)").categoryName, "吃饭")
        XCTAssertEqual(classify(merchant: "美团外卖").categoryName, "吃饭")
        XCTAssertEqual(classify(merchant: "肯德基").categoryName, "吃饭")
    }

    func testGame() {
        XCTAssertEqual(classify(merchant: "Steam").categoryName, "游戏")
        XCTAssertEqual(classify(merchant: "王者荣耀点券充值").categoryName, "游戏")
    }

    func testShopping() {
        XCTAssertEqual(classify(merchant: "淘宝").categoryName, "购物")
        XCTAssertEqual(classify(merchant: "京东商城").categoryName, "购物")
    }

    func testTransport() {
        XCTAssertEqual(classify(merchant: "滴滴出行").categoryName, "交通")
        XCTAssertEqual(classify(merchant: "12306").categoryName, "交通")
    }

    func testUtilities() {
        XCTAssertEqual(classify(merchant: "国家电网电费").categoryName, "水电")
        XCTAssertEqual(classify(merchant: "中国移动话费充值").categoryName, "水电")
    }

    func testIncomeOnlyGoesToIncomeCategory() {
        let result = classify(merchant: "公司", text: "工资", kind: .income)
        XCTAssertEqual(result.categoryName, "工资收入")
    }

    func testLearnedRuleWins() {
        let rules = [TextNormalizer.normalize("中石化"): "加油"]
        let result = classify(merchant: "中石化", rules: rules)
        XCTAssertEqual(result.categoryName, "加油")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.95)
    }

    func testUnknownMerchantFallsBack() {
        let result = classify(merchant: "某某不明商户")
        XCTAssertEqual(result.categoryName, "其他")
        XCTAssertLessThan(result.confidence, 0.5)
    }
}
