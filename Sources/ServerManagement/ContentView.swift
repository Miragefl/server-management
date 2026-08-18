import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: Store

    /// 侧栏选中项：服务器或服务（互斥）
    enum SidebarSelection: Hashable {
        case server(Server.ID)
        case service(Service.ID)
    }

    @State private var selection: SidebarSelection?
    @State private var didClearInitialFocus = false

    var body: some View {
        NavigationSplitView {
            ServerListView(selection: $selection)
        } detail: {
            switch selection {
            case .server(let id):
                if let server = store.server(id: id) {
                    ServerDetailView(server: server)
                } else {
                    emptyView
                }
            case .service(let id):
                if let service = store.service(id: id) {
                    ServiceDetailView(service: service)
                } else {
                    emptyView
                }
            case nil:
                emptyView
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        // 侧栏不再用 List 后，窗口变 key 时初始焦点会落到工具栏按钮上并画出蓝色焦点环；
        // 在窗口真正成为 key 之后再清空第一响应者（仅首次，onAppear 时机太早窗口还不是 key）
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard !didClearInitialFocus else { return }
            didClearInitialFocus = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "未选择",
            systemImage: "sidebar.left",
            description: Text("在左侧选择服务器或服务")
        )
    }
}
