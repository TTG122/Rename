//
//  RegexHelper.swift
//  轻点记账
//

import Foundation

enum RegexHelper {
    struct Match {
        let value: String
        let range: Range<String.Index>
        let groups: [String?]
    }

    static func matches(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> [Match] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: caseInsensitive ? [.caseInsensitive] : []
        ) else { return [] }

        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: nsRange).compactMap { result in
            guard let fullRange = Range(result.range, in: text) else { return nil }
            var groups: [String?] = []
            for index in 1..<result.numberOfRanges {
                if let range = Range(result.range(at: index), in: text) {
                    groups.append(String(text[range]))
                } else {
                    groups.append(nil)
                }
            }
            return Match(value: String(text[fullRange]), range: fullRange, groups: groups)
        }
    }

    static func firstMatch(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> Match? {
        matches(pattern, in: text, caseInsensitive: caseInsensitive).first
    }

    static func contains(_ pattern: String, in text: String) -> Bool {
        firstMatch(pattern, in: text) != nil
    }

    /// 用空格替换掉所有匹配内容（保持长度不变，便于后续按位置分析）
    static func blankOut(_ pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: nsRange,
            withTemplate: " "
        )
    }
}
