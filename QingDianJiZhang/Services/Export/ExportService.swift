//
//  ExportService.swift
//  轻点记账
//
//  导出：CSV / Excel / PDF / 长图。全部本地生成，不上传任何数据。
//

import Foundation
import SwiftUI
import UIKit

@MainActor
enum ExportService {

    // MARK: - CSV

    static func csvString(transactions: [Transaction]) -> String {
        let header = ["日期", "时间", "收支", "金额", "商户", "商品", "分类", "支付平台", "账户", "订单号", "备注", "来源", "识别置信度"]
        var lines = [header.map(escapeCSV).joined(separator: ",")]

        for item in transactions.sorted(by: { $0.occurredAt > $1.occurredAt }) {
            let calendar = Calendar.current
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.occurredAt)
            let dateText = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
            let timeText = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
            let row = [
                dateText,
                timeText,
                item.kind.title,
                MoneyFormatter.string(cents: item.amountCents),
                item.merchant,
                item.item,
                item.categoryName,
                item.platform.title,
                item.account,
                item.orderNumber,
                item.note,
                item.source.title,
                String(format: "%.2f", item.confidence)
            ]
            lines.append(row.map(escapeCSV).joined(separator: ","))
        }
        // BOM：让 Excel 正确识别 UTF-8
        return "\u{FEFF}" + lines.joined(separator: "\r\n")
    }

    private static func escapeCSV(_ value: String) -> String {
        let needsQuote = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuote ? "\"\(escaped)\"" : escaped
    }

    // MARK: - Excel

    static func xlsxData(transactions: [Transaction]) -> Data {
        var rows: [[String]] = [["日期", "时间", "收支", "金额", "商户", "商品", "分类", "支付平台", "账户", "订单号", "备注", "来源"]]
        let calendar = Calendar.current

        for item in transactions.sorted(by: { $0.occurredAt > $1.occurredAt }) {
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.occurredAt)
            rows.append([
                String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0),
                String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0),
                item.kind.title,
                MoneyFormatter.string(cents: item.amountCents),
                item.merchant,
                item.item,
                item.categoryName,
                item.platform.title,
                item.account,
                item.orderNumber,
                item.note,
                item.source.title
            ])
        }
        return XLSXWriter.make(sheetName: "账单", rows: rows, numericColumns: [3])
    }

    // MARK: - 临时文件

    static func writeTemporaryFile(data: Data, fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("轻点记账导出", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func exportCSVFile(transactions: [Transaction]) throws -> URL {
        let text = csvString(transactions: transactions)
        let name = "轻点记账-\(fileNameDate()).csv"
        return try writeTemporaryFile(data: Data(text.utf8), fileName: name)
    }

    static func exportXLSXFile(transactions: [Transaction]) throws -> URL {
        let data = xlsxData(transactions: transactions)
        return try writeTemporaryFile(data: data, fileName: "轻点记账-\(fileNameDate()).xlsx")
    }

    static func exportPDFFile(report: MonthlyReport) throws -> URL {
        let data = pdfData(report: report)
        return try writeTemporaryFile(
            data: data,
            fileName: "轻点记账-\(report.monthKey)-月报.pdf"
        )
    }

    private static func fileNameDate() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: .now)
    }

    // MARK: - PDF

    static func pdfData(report: MonthlyReport) -> Data {
        let pageSize = CGSize(width: 595, height: 842)      // A4 @72dpi
        let margin: CGFloat = 44
        let contentWidth = pageSize.width - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        return renderer.pdfData { context in
            var cursorY: CGFloat = margin
            context.beginPage()

            func newPageIfNeeded(_ needed: CGFloat) {
                if cursorY + needed > pageSize.height - margin {
                    context.beginPage()
                    cursorY = margin
                }
            }

            func draw(_ text: String, font: UIFont, color: UIColor, spacingAfter: CGFloat = 6) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 4
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                newPageIfNeeded(bounding.height + spacingAfter)
                (text as NSString).draw(
                    with: CGRect(x: margin, y: cursorY, width: contentWidth, height: bounding.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                cursorY += bounding.height + spacingAfter
            }

            func drawDivider() {
                newPageIfNeeded(12)
                UIColor(white: 0.88, alpha: 1).setFill()
                UIBezierPath(rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 1)).fill()
                cursorY += 12
            }

            let brand = UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
            let dark = UIColor(white: 0.09, alpha: 1)
            let gray = UIColor(white: 0.45, alpha: 1)

            // 标题
            draw("轻点记账 · \(report.monthTitle)月报", font: .systemFont(ofSize: 24, weight: .bold), color: dark, spacingAfter: 4)
            draw("由轻点记账自动生成 · 数据仅保存在本机", font: .systemFont(ofSize: 11), color: gray, spacingAfter: 18)

            // 核心数字
            draw("本月支出  ¥\(MoneyFormatter.grouped(cents: report.totalExpenseCents))", font: .systemFont(ofSize: 30, weight: .bold), color: brand, spacingAfter: 8)
            draw("收入 ¥\(MoneyFormatter.grouped(cents: report.totalIncomeCents))    结余 ¥\(MoneyFormatter.grouped(cents: report.balanceCents))    日均 ¥\(MoneyFormatter.grouped(cents: report.dailyAverageCents))",
                 font: .systemFont(ofSize: 13), color: gray, spacingAfter: 6)
            draw("共 \(report.transactionCount) 笔记录", font: .systemFont(ofSize: 12), color: gray, spacingAfter: 14)

            drawDivider()

            // 分类排行
            draw("分类排行", font: .systemFont(ofSize: 16, weight: .semibold), color: dark, spacingAfter: 10)
            for stat in report.categoryBreakdown.prefix(12) {
                let line = "\(stat.name)    ¥\(MoneyFormatter.grouped(cents: stat.amountCents))    \(Int(stat.ratio * 100))%    \(stat.count) 笔"
                draw(line, font: .systemFont(ofSize: 13), color: dark, spacingAfter: 5)
            }

            drawDivider()

            // 商户
            if !report.topMerchants.isEmpty {
                draw("常去商户", font: .systemFont(ofSize: 16, weight: .semibold), color: dark, spacingAfter: 10)
                for merchant in report.topMerchants {
                    draw("\(merchant.name)    ¥\(MoneyFormatter.grouped(cents: merchant.amountCents))    \(merchant.count) 次",
                         font: .systemFont(ofSize: 13), color: dark, spacingAfter: 5)
                }
                drawDivider()
            }

            // 总结
            draw("AI 月报总结", font: .systemFont(ofSize: 16, weight: .semibold), color: dark, spacingAfter: 10)
            draw(report.summaryText, font: .systemFont(ofSize: 13), color: dark, spacingAfter: 12)

            if !report.suggestions.isEmpty {
                draw("可以试试这些", font: .systemFont(ofSize: 16, weight: .semibold), color: dark, spacingAfter: 10)
                for (index, suggestion) in report.suggestions.enumerated() {
                    draw("\(index + 1). \(suggestion)", font: .systemFont(ofSize: 13), color: dark, spacingAfter: 6)
                }
            }

            if !report.subscriptions.isEmpty {
                drawDivider()
                draw("疑似连续订阅", font: .systemFont(ofSize: 16, weight: .semibold), color: dark, spacingAfter: 10)
                for item in report.subscriptions {
                    draw("\(item.name)    ¥\(MoneyFormatter.grouped(cents: item.amountCents))    \(item.categoryName)",
                         font: .systemFont(ofSize: 13), color: dark, spacingAfter: 5)
                }
            }
        }
    }

    // MARK: - 长图

    /// 用 ImageRenderer 把任意 SwiftUI 视图渲染成高清长图（3x）
    static func longImage<V: View>(_ view: V, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: 390, height: nil)
        return renderer.uiImage
    }

    static func saveLongImageToTemporary(_ image: UIImage) throws -> URL {
        guard let data = image.pngData() else {
            throw NSError(domain: "轻点记账", code: 500, userInfo: [NSLocalizedDescriptionKey: "长图生成失败"])
        }
        return try writeTemporaryFile(data: data, fileName: "轻点记账-月报-\(fileNameDate()).png")
    }
}
