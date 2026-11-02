//
//  SharedInbox.swift
//  轻点记账
//
//  App 与 Share Extension 之间的「收件箱」。使用 App Group 共享容器，
//  分享进来的截图先落到 Inbox，主 App 启动后扫描并逐条识别。
//

import Foundation

enum AppGroup {
    static let identifier = "group.com.qingdianjizhang.app"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isAvailable: Bool { containerURL != nil }

    /// App Group 不可用时的降级目录（App 自己的 Documents）
    static var fallbackURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    static var workingURL: URL? { containerURL ?? fallbackURL }
}

// MARK: - 收件箱

enum SharedInbox {
    struct Item: Codable, Identifiable, Equatable {
        var id: String
        var fileName: String
        var createdAt: Date
        var source: String
        /// 分享时系统可能直接给到文本（例如 App 分享的是文字而不是图片）
        var text: String?
        var note: String?

        var fileURL: URL? {
            guard !fileName.isEmpty, let dir = SharedInbox.inboxDirectory else { return nil }
            return dir.appendingPathComponent(fileName)
        }
    }

    private static let folderName = "Inbox"

    static var inboxDirectory: URL? {
        guard let base = AppGroup.workingURL else { return nil }
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: 写入

    @discardableResult
    static func enqueue(imageData: Data, source: String) -> Item? {
        guard let dir = inboxDirectory else { return nil }
        let id = UUID().uuidString
        let fileName = "\(id).png"
        let fileURL = dir.appendingPathComponent(fileName)
        do {
            try imageData.write(to: fileURL, options: .atomic)
        } catch {
            return nil
        }
        let item = Item(id: id, fileName: fileName, createdAt: .now, source: source, text: nil, note: nil)
        persist(item, in: dir)
        return item
    }

    @discardableResult
    static func enqueue(text: String, source: String) -> Item? {
        guard let dir = inboxDirectory else { return nil }
        let id = UUID().uuidString
        let item = Item(id: id, fileName: "", createdAt: .now, source: source, text: text, note: nil)
        persist(item, in: dir)
        return item
    }

    private static func persist(_ item: Item, in dir: URL) {
        let metaURL = dir.appendingPathComponent("\(item.id).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(item) {
            try? data.write(to: metaURL, options: .atomic)
        }
    }

    // MARK: 读取

    static func pendingItems() -> [Item] {
        guard let dir = inboxDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Item? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Item.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func imageData(for item: Item) -> Data? {
        guard let url = item.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    static func pendingCount() -> Int {
        pendingItems().count
    }

    // MARK: 清理

    static func remove(_ item: Item) {
        guard let dir = inboxDirectory else { return }
        if let url = item.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(item.id).json"))
    }

    static func clear() {
        for item in pendingItems() {
            remove(item)
        }
    }
}
