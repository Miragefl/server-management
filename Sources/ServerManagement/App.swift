import SwiftUI

@main
struct ServerManagementApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.sizeCategory, .large)
        }
    }
}
