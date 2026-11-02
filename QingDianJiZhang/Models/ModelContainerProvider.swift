//
//  ModelContainerProvider.swift
//  轻点记账
//

import Foundation
import SwiftData

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Transaction.self,
        Category.self,
        MerchantRule.self,
        Budget.self
    ]

    static var schema: Schema { Schema(models) }
}

enum ModelContainerProvider {
    /// iCloud 容器标识。需要和 Xcode Capabilities 里创建的容器一致。
    static let cloudKitContainerIdentifier = "iCloud.com.qingdianjizhang.app"

    /// 设置页开关写入的 key（与 SettingsStore 保持一致）
    static let iCloudFlagKey = "settings.iCloudSync"

    /// App 全局容器
    static let shared: ModelContainer = make()

    private static func make() -> ModelContainer {
        let wantsCloud = UserDefaults.standard.bool(forKey: iCloudFlagKey)

        // 1. 优先按用户偏好创建
        if wantsCloud {
            let cloudConfig = ModelConfiguration(
                "QingDianJiZhang",
                schema: AppSchema.schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .private(cloudKitContainerIdentifier)
            )
            if let container = try? ModelContainer(for: AppSchema.schema, configurations: [cloudConfig]) {
                return container
            }
            #if DEBUG
            print("[轻点记账] CloudKit 容器不可用（多半是没在 Xcode 里开启 iCloud Capability），回落到本地库")
            #endif
        }

        // 2. 本地库
        let localConfig = ModelConfiguration(
            "QingDianJiZhang",
            schema: AppSchema.schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        if let container = try? ModelContainer(for: AppSchema.schema, configurations: [localConfig]) {
            return container
        }

        // 3. 最后兜底：内存库。宁可这次不持久化，也不要启动即崩溃。
        #if DEBUG
        print("[轻点记账] 本地库创建失败，降级为内存库")
        #endif
        let memoryConfig = ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: AppSchema.schema, configurations: [memoryConfig])
        } catch {
            fatalError("无法创建任何 SwiftData 容器：\(error)")
        }
    }

    /// 单元测试用
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: AppSchema.schema, configurations: [configuration])
    }
}

// MARK: - 首次启动初始化

enum SeedData {
    static func prepare(context: ModelContext) {
        seedCategoriesIfNeeded(context: context)
        seedDefaultBudgetIfNeeded(context: context)
    }

    static func seedCategoriesIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        guard existing.isEmpty else { return }

        for (index, def) in SystemCategories.all.enumerated() {
            let category = Category(
                name: def.name,
                symbolName: def.symbol,
                colorHex: def.color,
                scope: def.scope,
                isSystem: true,
                sortIndex: index
            )
            context.insert(category)
        }
        try? context.save()
    }

    static func seedDefaultBudgetIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        guard existing.isEmpty else { return }
        // 默认给一个 3000 元的总预算，用户可在设置里改
        let budget = Budget(monthKey: "", amountCents: 300_000)
        context.insert(budget)
        try? context.save()
    }

    /// 按名称取分类（大小写 / 空白不敏感）
    static func category(named name: String, in categories: [Category]) -> Category? {
        let target = TextNormalizer.normalize(name)
        guard !target.isEmpty else { return nil }
        if let exact = categories.first(where: { TextNormalizer.normalize($0.name) == target }) {
            return exact
        }
        return categories.first { TextNormalizer.normalize($0.name).contains(target) }
    }
}
