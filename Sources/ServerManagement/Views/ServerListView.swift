import SwiftUI

/// 左栏：服务器 / 服务 双区块列表
struct ServerListView: View {
    @EnvironmentObject private var store: Store
    @Binding var selection: ContentView.SidebarSelection?

    @State private var keyword = ""
    @State private var editingServer: Server?
    @State private var isAdding = false
    @State private var isImporting = false
    @State private var serverPendingDelete: Server?
    @State private var isShowingSettings = false
    @State private var isShowingAppSettings = false

    // 服务区块状态
    @State private var editingService: Service?
    @State private var isAddingService = false
    @State private var servicePendingDelete: Service?

    // 区块折叠状态（服务器默认收起）
    @State private var serversExpanded = false
    @State private var servicesExpanded = true

    // 分组手风琴状态：当前展开的分组名（nil = 全收起）；默认展开第一个分组
    @State private var expandedServerGroup: String?
    @State private var expandedServiceGroup: String?

    /// 当前悬停行（单一数据源；行视图被收起移除时 onHover 退出事件不可靠，集中管理便于清理）
    @State private var hovered: ContentView.SidebarSelection?

    private var filteredServers: [Server] {
        store.filteredServers(keyword: keyword)
    }

    private var filteredServices: [Service] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.services }
        let lower = query.lowercased()
        return store.services.filter {
            $0.name.lowercased().contains(lower)
                || $0.envs.contains { $0.lowercased().contains(lower) }
                || $0.installMethod.lowercased().contains(lower)
                || $0.group.lowercased().contains(lower)
        }
    }

    var body: some View {
        // 用 pinnedViews 让「服务器 / 服务」区块头吸顶，滚动时不消失
        // （macOS 上 List 的 Section header 不固定，会随内容滚走）
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                serverSection
                serviceSection
            }
            .padding(.vertical, 4)
            .background(ScrollBarHider())
        }
        .scrollIndicators(.hidden)
        .searchable(text: $keyword, prompt: Text("多关键字空格分隔，如：kafka sit"))
        .onChange(of: keyword) { _, _ in hovered = nil }
        .onAppear(perform: expandFirstGroupsIfNeeded)
        .overlay {
            if filteredServers.isEmpty && filteredServices.isEmpty {
                ContentUnavailableView.search(text: keyword)
            }
        }
        .toolbar {
            ToolbarItem {
                UpdateButton()
            }
            ToolbarItem {
                Menu {
                    Button {
                        isAdding = true
                    } label: {
                        Label("单台新增服务器…", systemImage: "plus")
                    }
                    Button {
                        isImporting = true
                    } label: {
                        Label("批量导入服务器…", systemImage: "square.stack.3d.up")
                    }
                    Divider()
                    Button {
                        isAddingService = true
                    } label: {
                        Label("新增服务…", systemImage: "shippingbox")
                    }
                    Divider()
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("环境 / 系统 / 分组…", systemImage: "gearshape")
                    }
                    Button {
                        isShowingAppSettings = true
                    } label: {
                        Label("网络代理…", systemImage: "network")
                    }
                } label: {
                    Label("新增", systemImage: "plus")
                }
                .focusEffectDisabled()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            DictionarySettingsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $isShowingAppSettings) {
            AppSettingsView()
        }
        .sheet(isPresented: $isAdding) {
            ServerEditView(server: nil)
        }
        .sheet(isPresented: $isImporting) {
            ServerImportView()
                .environmentObject(store)
        }
        .sheet(isPresented: $isAddingService) {
            ServiceEditView(service: nil)
        }
        .sheet(item: $editingServer) { server in
            ServerEditView(server: server)
        }
        .sheet(item: $editingService) { service in
            ServiceEditView(service: service)
        }
        .alert(
            "删除服务器",
            isPresented: Binding(
                get: { serverPendingDelete != nil },
                set: { if !$0 { serverPendingDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let server = serverPendingDelete {
                    store.deleteServer(server)
                    if selection == .server(server.id) {
                        selection = nil
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将解除「\(serverPendingDelete?.hostname ?? "")」上的服务绑定（服务记录保留），此操作不可撤销。")
        }
        .alert(
            "删除服务",
            isPresented: Binding(
                get: { servicePendingDelete != nil },
                set: { if !$0 { servicePendingDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let service = servicePendingDelete {
                    store.deleteService(service)
                    if selection == .service(service.id) {
                        selection = nil
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            let count = servicePendingDelete.map { store.bindingCount(of: $0.id) } ?? 0
            return Text("将删除服务「\(servicePendingDelete?.name ?? "")」并解除其与 \(count) 台服务器的绑定，此操作不可撤销。")
        }
    }

    // MARK: - 区块

    /// 分组顺序：字典序 + 未分组垫底（仅有未分组项时展示）
    private var serverGroupOrder: [String] {
        var names = store.groupDefinitions.map(\.name)
        let known = Set(names)
        names.append(contentsOf: filteredServers.map(\.group).filter { !$0.isEmpty && !known.contains($0) })
        if filteredServers.contains(where: { $0.group.isEmpty }) {
            names.append("")
        }
        return names
    }

    private var serviceGroupOrder: [String] {
        var names = store.groupDefinitions.map(\.name)
        let known = Set(names)
        names.append(contentsOf: filteredServices.map(\.group).filter { !$0.isEmpty && !known.contains($0) })
        if filteredServices.contains(where: { $0.group.isEmpty }) {
            names.append("")
        }
        return names
    }

    private var serverSection: some View {
        Section {
            if serversExpanded {
                ForEach(serverGroupOrder, id: \.self) { group in
                    let members = filteredServers.filter { $0.group == group }
                    if !members.isEmpty {
                        groupHeader(
                            name: group,
                            count: members.count,
                            isExpanded: expandedServerGroup == group
                        ) { toggleServerGroup(group) }
                        if expandedServerGroup == group {
                            ForEach(members) { server in
                                sidebarRow(serverRow(server), id: .server(server.id)) {
                                    Button("编辑…") { editingServer = server }
                                    Divider()
                                    Button("删除…", role: .destructive) { serverPendingDelete = server }
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            sectionHeader(
                title: "服务器",
                count: filteredServers.count,
                icon: "server.rack",
                isExpanded: serversExpanded
            ) {
                hovered = nil
                serversExpanded.toggle()
            }
        }
    }

    private var serviceSection: some View {
        Section {
            if servicesExpanded {
                ForEach(serviceGroupOrder, id: \.self) { group in
                    let members = filteredServices.filter { $0.group == group }
                    if !members.isEmpty {
                        groupHeader(
                            name: group,
                            count: members.count,
                            isExpanded: expandedServiceGroup == group
                        ) { toggleServiceGroup(group) }
                        if expandedServiceGroup == group {
                            ForEach(members) { service in
                                sidebarRow(serviceRow(service), id: .service(service.id)) {
                                    Button("编辑…") { editingService = service }
                                    Divider()
                                    Button("删除…", role: .destructive) { servicePendingDelete = service }
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            sectionHeader(
                title: "服务",
                count: filteredServices.count,
                icon: "shippingbox",
                isExpanded: servicesExpanded
            ) {
                hovered = nil
                servicesExpanded.toggle()
            }
        }
    }

    /// 手风琴切换：点已展开组收起，点其他组展开并收起其余（行被移除时 onHover 退出不可靠，顺手清悬停）
    private func toggleServerGroup(_ group: String) {
        hovered = nil
        expandedServerGroup = expandedServerGroup == group ? nil : group
    }

    private func toggleServiceGroup(_ group: String) {
        hovered = nil
        expandedServiceGroup = expandedServiceGroup == group ? nil : group
    }

    /// 首次进入默认展开第一个分组（仅初始化一次；之后跟随用户操作）
    private func expandFirstGroupsIfNeeded() {
        if expandedServerGroup == nil {
            expandedServerGroup = serverGroupOrder.first
        }
        if expandedServiceGroup == nil {
            expandedServiceGroup = serviceGroupOrder.first
        }
    }

    /// 分组小标题（空名 = 未分组；不吸顶，随内容滚动；点击手风琴展开/收起）
    private func groupHeader(name: String, count: Int, isExpanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Image(systemName: name.isEmpty ? "tray" : "folder")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(name.isEmpty ? "未分组" : name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .padding(.top, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 行容器：点击选中 + 选中/悬停高亮 + 右键菜单（替代 List 原生 selection）
    private func sidebarRow(_ content: some View, id: ContentView.SidebarSelection, @ViewBuilder menu: () -> some View) -> some View {
        content
            .modifier(SidebarRowHighlight(isSelected: selection == id, isHovered: hovered == id))
            .contentShape(Rectangle())
            .onTapGesture { selection = id }
            .onHover { entering in
                if entering {
                    hovered = id
                } else if hovered == id {
                    hovered = nil
                }
            }
            .contextMenu(menuItems: menu)
            .padding(.horizontal, 8)
    }

    // MARK: - 行视图

    /// 可点击折叠的区块头：图标 + 标题 + 计数 + 折叠箭头（吸顶时靠材质背景遮挡滚动内容）
    private func sectionHeader(title: String, count: Int, icon: String, isExpanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text("(\(count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(.ultraThinMaterial, in: Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func serverRow(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(server.hostname).font(.body.weight(.semibold))
                Spacer()
                Text("\(store.boundServices(of: server.id).count) 个服务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(server.primaryIP).font(.callout).foregroundStyle(.secondary)
                if !server.os.isEmpty {
                    Text(server.os)
                        .font(.caption)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func serviceRow(_ service: Service) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(service.name).font(.body.weight(.semibold))
                Spacer()
                Text("\(store.bindingCount(of: service.id)) 台")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(service.envs.sorted(), id: \.self) { env in
                    Text(env.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(store.color(for: env).opacity(0.14), in: Capsule())
                        .foregroundStyle(store.color(for: env))
                }
                if !service.ports.isEmpty {
                    Text(":\(service.ports.map(\.port).map(String.init).joined(separator: "/"))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 环境配色：prod 红 / uat 橙 / sit 蓝 / 其他灰
}

/// 侧栏行高亮（纯展示，状态由父视图管理）：选中淡强调色、悬停淡灰
private struct SidebarRowHighlight: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.2))
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.06))
                }
            }
    }
}

/// 兜底隐藏宿主 NSScrollView 的滚动条
/// （SwiftUI .scrollIndicators(.hidden) 在侧栏容器内、内容展开重建 scroller 时有失效场景；
///   关闭 NSScroller 不影响滚轮 / 触控板滚动）
private struct ScrollBarHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            // 从占位视图沿 superview 链向上找最近的 NSScrollView（即本 SwiftUI ScrollView 的桥接宿主）
            var current: NSView? = view
            while let candidate = current {
                if let scrollView = candidate as? NSScrollView {
                    scrollView.hasVerticalScroller = false
                    scrollView.hasHorizontalScroller = false
                    break
                }
                current = candidate.superview
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
