import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store

    /// 侧栏选中项：服务器或服务（互斥）
    enum SidebarSelection: Hashable {
        case server(Server.ID)
        case service(Service.ID)
    }

    @State private var selection: SidebarSelection?

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
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "未选择",
            systemImage: "sidebar.left",
            description: Text("在左侧选择服务器或服务")
        )
    }
}
