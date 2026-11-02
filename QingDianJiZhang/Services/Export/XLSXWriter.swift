//
//  XLSXWriter.swift
//  简记
//
//  生成最小可用的 .xlsx（Office Open XML）。Excel / Numbers / WPS 都能直接打开。
//

import Foundation

enum XLSXWriter {

    /// rows[0] 作为表头
    /// numericColumns：需要写成数字的列下标（0 起）
    static func make(
        sheetName: String = "账单",
        rows: [[String]],
        numericColumns: Set<Int> = []
    ) -> Data {
        let entries: [ZipWriter.Entry] = [
            .init(path: "[Content_Types].xml", data: Data(contentTypesXML.utf8)),
            .init(path: "_rels/.rels", data: Data(rootRelsXML.utf8)),
            .init(path: "xl/workbook.xml", data: Data(workbookXML(sheetName: sheetName).utf8)),
            .init(path: "xl/_rels/workbook.xml.rels", data: Data(workbookRelsXML.utf8)),
            .init(path: "xl/worksheets/sheet1.xml", data: Data(sheetXML(rows: rows, numericColumns: numericColumns).utf8))
        ]
        return ZipWriter.make(entries: entries)
    }

    // MARK: - 静态部件

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
    </Relationships>
    """

    private static func workbookXML(sheetName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <sheets><sheet name="\(escape(sheetName))" sheetId="1" r:id="rId1"/></sheets>\
        </workbook>
        """
    }

    // MARK: - 表格

    private static func sheetXML(rows: [[String]], numericColumns: Set<Int>) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <sheetData>
        """

        for (rowIndex, row) in rows.enumerated() {
            let rowNumber = rowIndex + 1
            xml += "<row r=\"\(rowNumber)\">"
            for (columnIndex, value) in row.enumerated() {
                let reference = "\(columnLetter(columnIndex))\(rowNumber)"
                if numericColumns.contains(columnIndex),
                   let number = Double(value.replacingOccurrences(of: ",", with: "")),
                   value.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil {
                    xml += "<c r=\"\(reference)\"><v>\(number)</v></c>"
                } else {
                    xml += "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
                }
            }
            xml += "</row>"
        }

        xml += "</sheetData></worksheet>"
        return xml
    }

    // MARK: - 工具

    static func columnLetter(_ index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var value = max(index, 0)
        var result = ""
        repeat {
            let remainder = value % 26
            result = String(letters[remainder]) + result
            value = value / 26 - 1
        } while value >= 0
        return result
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
