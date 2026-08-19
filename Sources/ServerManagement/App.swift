import SwiftUI

@main
struct ServerManagementApp: App {
    @StateObject private var store = Store()
    @StateObject private var appSettings: AppSettings
    @StateObject private var updateChecker: UpdateChecker

    init() {
        let settings = AppSettings()
        _appSettings = StateObject(wrappedValue: settings)
        _updateChecker = StateObject(wrappedValue: UpdateChecker(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(appSettings)
                .environmentObject(updateChecker)
                .environment(\.sizeCategory, .large)
                .task {
                    // 启动后延迟静默检查，不抢启动网络与注意力
                    try? await Task.sleep(for: .seconds(5))
                    if updateChecker.state == .idle {
                        await updateChecker.checkForUpdates()
                    }
                }
        }
    }
}
