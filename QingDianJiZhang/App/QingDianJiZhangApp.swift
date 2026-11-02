//
//  QingDianJiZhangApp.swift
//  简记
//
//  App 入口。SwiftData 容器在这里注入，路由与设置以 Environment 下发。
//

import SwiftUI
import SwiftData

@main
struct QingDianJiZhangApp: App {
    @State private var router = AppRouter.shared
    @State private var settings = SettingsStore.shared

    private let container = ModelContainerProvider.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(settings)
                .modelContainer(container)
                .tint(Theme.brand)
                .preferredColorScheme(nil)
        }
    }
}
