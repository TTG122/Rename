//
//  XLSXReader.swift
//  简记
//
//  读取 .xlsx 的第一个工作表，输出字符串二维数组。
//  只依赖 Foundation 的 XMLParser + 系统 Compression，无第三方库。
//

import Foundation

enum XLSXReaderError: LocalizedError {
    case emptyWorkbook
    case noSheet
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyWorkbook: return "工作簿是空的"
        case .noSheet: return "找不到工作表，请确认文件没有加密"
        case .parseFailed(let message): return "解析失败：\(message)"
        }
    }
}

enum XLSXReader {

    static func rows(from data: Data) throws -> [[String]] {
        let parts = try ZipReader.unzip(data)

        guard let sheetKey = parts.keys
            .filter({ $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") })
            .sorted()
            .first, let sheetData = parts[sheetKey]
        else {
            throw XLSXReaderError.noSheet
        }

        var sharedStrings: [String] = []
        if let sharedData = parts["xl/sharedStrings.xml"] {
            let parser = SharedStringsParser()
            if parser.parse(data: sharedData) {
                sharedStrings = parser.strings
            }
        }

        let parser = SheetParser(sharedStrings: sharedStrings)
        guard parser.parse(data: sheetData) else {
            throw XLSXReaderError.parseFailed("工作表 XML 无法解析")
        }

        let rows = parser.normalizedRows
        guard !rows.isEmpty else { throw XLSXReaderError.emptyWorkbook }
        return rows
    }
}

// MARK: - sharedStrings.xml

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private(set) var strings: [String] = []
    private var current = ""
    private var isInsideItem = false
    private var isInsideText = false

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "si":
            isInsideItem = true
            current = ""
        case "t":
            isInsideText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideItem && isInsideText {
            current += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "si":
            strings.append(current)
            isInsideItem = false
        case "t":
            isInsideText = false
        default:
            break
        }
    }
}

// MARK: - sheet1.xml

private final class SheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [[String]] = []
    private var currentRow: [String] = []
    private var currentColumnIndex = 0
    private var currentValue = ""
    private var currentCellType = ""
    private var isInsideValue = false
    private var isInsideText = false
    private var isInsideCell = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    var normalizedRows: [[String]] {
        // 去掉完全空白的行，并补齐每行列数
        let filtered = rows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let maxCount = filtered.map(\.count).max() ?? 0
        return filtered.map { row in
            var copy = row
            if copy.count < maxCount {
                copy.append(contentsOf: Array(repeating: "", count: maxCount - copy.count))
            }
            return copy
        }
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "row":
            currentRow = []
            currentColumnIndex = 0
        case "c":
            isInsideCell = true
            currentValue = ""
            currentCellType = attributeDict["t"] ?? ""
            if let reference = attributeDict["r"] {
                currentColumnIndex = Self.columnIndex(from: reference)
            }
        case "v":
            isInsideValue = true
        case "t":
            isInsideText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideValue || isInsideText {
            currentValue += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "v":
            isInsideValue = false
        case "t":
            isInsideText = false
        case "c":
            isInsideCell = false
            var value = currentValue
            if currentCellType == "s", let index = Int(value), index >= 0, index < sharedStrings.count {
                value = sharedStrings[index]
            }
            write(value, at: currentColumnIndex)
            currentValue = ""
        case "row":
            rows.append(currentRow)
        default:
            break
        }
    }

    // MARK: 内部

    private func write(_ value: String, at index: Int) {
        guard index >= 0, index < 4096 else { return }
        if currentRow.count <= index {
            currentRow.append(contentsOf: Array(repeating: "", count: index - currentRow.count + 1))
        }
        currentRow[index] = value
    }

    /// "AB12" → 27（0 起）
    static func columnIndex(from reference: String) -> Int {
        let letters = reference.prefix { $0.isLetter }
        var index = 0
        for scalar in letters.uppercased().unicodeScalars {
            let value = scalar.value
            guard value >= 65, value <= 90 else { continue }
            index = index * 26 + Int(value - 64)
        }
        return max(index - 1, 0)
    }
}
