//
//  SharedInboxSupport.swift
//  轻点记账 · 分享扩展
//
//  注意：这个文件是主 App 里 SharedInbox.swift 的精简副本。
//  扩展是独立 target，不能直接链接主 App 的代码，复制一份最省事，
//  但要保证 App Group identifier 与文件名规则一致。
//

import Foundation

enum SharedInboxSupport {

    static let appGroupIdentifier = "group.com.qingdianjizhang.app"

    private static var baseURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    private static var inboxDirectory: URL? {
        guard let base = baseURL else { return nil }
        let dir = base.appendingPathComponent("Inbox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    @discardableResult
    static func enqueue(imageData: Data, source: String) -> Bool {
        guard let dir = inboxDirectory else { return false }
        let id = UUID().uuidString
        let fileURL = dir.appendingPathComponent("\(id).png")
        do {
            try imageData.write(to: fileURL, options: .atomic)
        } catch {
            return false
        }
        writeMeta(id: id, fileName: "\(id).png", source: source, text: nil, in: dir)
        return true
    }

    @discardableResult
    static func enqueue(text: String, source: String) -> Bool {
        guard let dir = inboxDirectory else { return false }
        let id = UUID().uuidString
        writeMeta(id: id, fileName: "", source: source, text: text, in: dir)
        return true
    }

    private static func writeMeta(id: String, fileName: String, source: String, text: String?, in dir: URL) {
        let payload: [String: Any] = [
            "id": id,
            "fileName": fileName,
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "source": source,
            "text": text ?? ""
        ]
        // 与主 App 的 Codable 结构保持一致：text 用可选，这里写空字符串时主 App 会当成空文本忽略
        var dictionary = payload
        if text == nil { dictionary["text"] = nil }
        if let data = try? JSONSerialization.data(withJSONObject: dictionary) {
            try? data.write(to: dir.appendingPathComponent("\(id).json"), options: .atomic)
        }
    }
}
