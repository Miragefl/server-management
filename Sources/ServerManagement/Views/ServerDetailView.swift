import SwiftUI

/// 右栏：服务器详情（信息头原地编辑 + 已绑定服务表格 + 环境多选筛选）
struct ServerDetailView: View {
    @EnvironmentObject private var store: Store
    let server: Server

    // 原地编辑字段
    @State private var hostname = ""
    @State private var ips: [String] = []
    @State private var os = ""
    @State private var cpu = ""
    @State private var cpuUnit = "C"
    @State private var memory = ""
    @State private var memoryUnit = "G"
    @State private var disk = ""
    @State private var credentials: [Credential] = []
    @State private var remark = ""
    @State private var loadedServerID: Server.ID?

    /// 多选环境筛选；空集合表示全部
    @State private var envFilters: Set<String> = []
    @State private var isPickingService = false
    @State private var editingService: Service?
    @State private var selectedServiceID: Service.ID?
    @State private var deploymentPendingUnbind: Service?
    @State private var serverPendingDelete = false

    private var visibleServices: [Service] {
        store.boundServices(of: server.id, envs: envFilters)
    }

    private var filterLabel: String {
        envFilters.isEmpty
            ? "全部环境"
            : envFilters.sorted().map { $0.uppercased() }.joined(separator: "、")
    }

    var body: some View {
        VStack(spacing: 0) {
            infoHeader

            Divider()

            credentialsSection

            Divider()

            serviceToolbar

            serviceTable
        }
        .sheet(isPresented: $isPickingService) {
            ServicePickerView(server: currentServer).environmentObject(store)
        }
        .sheet(item: $editingService) { service in
            ServiceEditView(service: service)
        }
        .alert(
            "删除服务器",
            isPresented: $serverPendingDelete
        ) {
            Button("删除", role: .destructive) {
                store.deleteServer(currentServer)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将解除「\(server.hostname)」上的服务绑定（服务记录保留），此操作不可撤销。")
        }
        .alert(
            "解除绑定",
            isPresented: Binding(
                get: { deploymentPendingUnbind != nil },
                set: { if !$0 { deploymentPendingUnbind = nil } }
            )
        ) {
            Button("解绑", role: .destructive) {
                if let service = deploymentPendingUnbind,
                   let deployment = store.binding(serverID: server.id, serviceID: service.id) {
                    store.unbind(deployment)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将「\(deploymentPendingUnbind?.name ?? "")」从 \(server.hostname) 上解绑。服务记录保留，可随时重新绑定。")
        }
    }

    /// 当前 Store 里的最新服务器数据（可能正被原地编辑更新）
    private var currentServer: Server {
        store.server(id: server.id) ?? server
    }

    // MARK: - 信息头（原地编辑）

    private var infoHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    TextField("Hostname", text: $hostname)
                        .font(.title2.bold())
                        .fixedSize()
                        .textFieldStyle(.plain)
                        .onChange(of: hostname) { _, _ in saveIfLoaded() }
                    Button(role: .destructive) {
                        serverPendingDelete = true
                    } label: {
                        Label("删除", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("删除服务器（解除服务绑定，服务保留）")
                }

                HStack(spacing: 10) {
                    ipsRow
                    osTag
                }

                groupTag

                HStack(spacing: 10) {
                    cpuTag
                    memoryTag
                    infoEditableTag("硬盘", text: $disk)
                }

                TextField("添加备注…", text: $remark, axis: .vertical)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...2)
                    .textFieldStyle(.plain)
                    .onChange(of: remark) { _, _ in saveIfLoaded() }
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: load)
        .onChange(of: server.id) { _, _ in load() }
    }

    /// 多 IP：inline 编辑 + 添加/移除（首个为主 IP）
    private var ipsRow: some View {
        HStack(spacing: 2) {
            Text("IP").foregroundStyle(.secondary)
            ForEach(ips.indices, id: \.self) { index in
                TextField("IP", text: Binding(
                    get: { ips[index] },
                    set: { ips[index] = $0; saveIfLoaded() }
                ))
                .font(.system(.callout, design: .monospaced))
                .fixedSize()
                .textFieldStyle(.plain)
            }
            Menu {
                Button("添加 IP…") { ips.append("") }
                if ips.count > 1 {
                    Divider()
                    ForEach(ips.indices, id: \.self) { index in
                        Button("移除 \(ips[index].isEmpty ? "空 IP" : ips[index])") {
                            _ = ips.remove(at: index)
                            saveIfLoaded()
                        }
                    }
                }
            } label: {
                Image(systemName: "plus.circle.dashed")
                    .font(.caption2)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.callout)
    }

    /// CPU：数值 + 单位下拉
    private var cpuTag: some View {
        HStack(spacing: 2) {
            Text("CPU").foregroundStyle(.secondary)
            TextField("—", text: $cpu)
                .fixedSize()
                .monospacedDigit()
                .textFieldStyle(.plain)
                .onChange(of: cpu) { _, _ in saveIfLoaded() }
            unitMenu(selection: $cpuUnit, units: ServerEditView.cpuUnits)
                .onChange(of: cpuUnit) { _, _ in saveIfLoaded() }
        }
        .font(.callout)
    }

    /// 内存：数值 + 单位下拉
    private var memoryTag: some View {
        HStack(spacing: 2) {
            Text("内存").foregroundStyle(.secondary)
            TextField("—", text: $memory)
                .fixedSize()
                .monospacedDigit()
                .textFieldStyle(.plain)
                .onChange(of: memory) { _, _ in saveIfLoaded() }
            unitMenu(selection: $memoryUnit, units: ServerEditView.memoryUnits)
                .onChange(of: memoryUnit) { _, _ in saveIfLoaded() }
        }
        .font(.callout)
    }

    /// 单位选择（与其他下拉统一样式：borderlessButton Menu + 系统指示箭头）
    private func unitMenu(selection: Binding<String>, units: [String]) -> some View {
        Menu {
            ForEach(units, id: \.self) { unit in
                Button(unit) { selection.wrappedValue = unit }
            }
        } label: {
            Text(selection.wrappedValue)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.caption)
    }

    private func infoEditableTag(_ label: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            TextField("—", text: text)
                .fixedSize()
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textFieldStyle(.plain)
                .onChange(of: text.wrappedValue) { _, _ in saveIfLoaded() }
        }
        .font(.callout)
    }

    private var osTag: some View {
        HStack(spacing: 2) {
            Text("系统").foregroundStyle(.secondary)
            TextField("—", text: $os)
                .fixedSize()
                .textFieldStyle(.plain)
                .onChange(of: os) { _, _ in saveIfLoaded() }
            Menu {
                ForEach(store.osDefinitions) { candidate in
                    Button(candidate.name) { os = candidate.name }
                }
                if !os.isEmpty {
                    Divider()
                    Button("清空") { os = "" }
                }
            } label: {
                ChevronOnlyLabel()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.callout)
    }

    /// 分组徽章：点开切换（未分组 + 字典候选），选中即写入 Store
    /// （macOS 15+ borderlessButton Menu 自带下拉箭头，label 用当前值即可）
    private var groupTag: some View {
        HStack(spacing: 6) {
            Text("分组").foregroundStyle(.secondary)
            Menu {
                Button("未分组") { setGroup("") }
                Divider()
                ForEach(store.groupDefinitions) { candidate in
                    Button(candidate.name) { setGroup(candidate.name) }
                }
            } label: {
                Text(currentServer.group.isEmpty ? "—" : currentServer.group)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(currentServer.group.isEmpty ? 0 : 0.14), in: Capsule())
                    .foregroundStyle(currentServer.group.isEmpty ? .secondary : Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.callout)
        .help("切换分组（字典在「环境 / 系统 / 分组」设置中维护）")
    }

    private func setGroup(_ name: String) {
        var target = currentServer
        target.group = name
        store.upsertServer(target)
    }

    /// 凭据区（标题 + 复用组件；变化写回 Store）
    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("账号（\(credentials.count)）")
                .font(.headline)
            CredentialsSectionView(credentials: $credentials) {
                saveIfLoaded()
            }
            .padding(.trailing, 16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 服务区

    private var serviceToolbar: some View {
        HStack {
            Text("已绑定服务（\(visibleServices.count)）")
                .font(.headline)
            Button {
                isPickingService = true
            } label: {
                Label("绑定服务", systemImage: "link")
            }
            .buttonStyle(.borderless)
            .help("从服务库多选部署到本机")
            HStack(spacing: 2) {
                Button {
                    editingService = visibleServices.first { $0.id == selectedServiceID }
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .disabled(selectedService == nil)
                .help("编辑选中的服务（全局生效）")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            Spacer()
            Menu {
                Button("全部环境") { envFilters = [] }
                    .disabled(envFilters.isEmpty)
                ForEach(store.allEnvs, id: \.self) { env in
                    Toggle(env.uppercased(), isOn: Binding(
                        get: { envFilters.contains(env) },
                        set: { on in
                            if on { envFilters.insert(env) } else { envFilters.remove(env) }
                        }
                    ))
                }
            } label: {
                Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var selectedService: Service? {
        visibleServices.first { $0.id == selectedServiceID }
    }

    private var serviceTable: some View {
        Table(visibleServices, selection: $selectedServiceID) {
            TableColumn("服务名") { service in
                HStack(spacing: 8) {
                    Text(service.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(service.name)
                    Spacer(minLength: 0)
                    Button(role: .destructive) {
                        deploymentPendingUnbind = service
                    } label: {
                        Text("解绑")
                    }
                    .font(.callout)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("从本机解绑（服务保留）")
                }
            }
            .width(min: 150, ideal: 190)
            TableColumn("环境") { service in
                HStack(spacing: 4) {
                    ForEach(service.envs.sorted(), id: \.self) { env in
                        Text(env.uppercased())
                            .font(.caption)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(store.color(for: env).opacity(0.18), in: Capsule())
                            .foregroundStyle(store.color(for: env))
                    }
                }
            }
            .width(min: 110, ideal: 140)
            TableColumn("端口") { service in
                if service.ports.isEmpty {
                    Text("—").foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(service.ports) { p in
                            HStack(spacing: 4) {
                                Text(String(p.port)).monospaced()
                                if !p.remark.isEmpty {
                                    Text(p.remark)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .width(min: 90, ideal: 150)
            TableColumn("安装方式") { service in
                if service.installMethod.isEmpty {
                    Text("—").foregroundStyle(.tertiary)
                } else {
                    Text(service.installMethod)
                }
            }
            .width(min: 100, ideal: 130)
            TableColumn("备注") { service in
                Text(service.remark)
                    .foregroundStyle(service.remark.isEmpty ? .tertiary : .primary)
            }
        }
        .overlay {
            if visibleServices.isEmpty {
                ContentUnavailableView(
                    "未绑定服务",
                    systemImage: "shippingbox",
                    description: Text("点击右上角「绑定服务」从服务库选择部署到本机的服务")
                )
            }
        }
        .contextMenu(forSelectionType: Service.self) { selection in
            if let service = selection.first {
                Button("编辑…") { editingService = service }
                Divider()
                Button("解绑…", role: .destructive) { deploymentPendingUnbind = service }
            }
        } primaryAction: { selection in
            if let service = selection.first {
                editingService = service
            }
        }
    }

    // MARK: - 加载与即时保存

    private func load() {
        hostname = server.hostname
        ips = server.ips
        os = server.os
        // 拆数值与单位（如 "8C" → 8 + C）；无单位串整体放数值框
        let parsedCPU = parseValueUnit(server.cpu, units: ServerEditView.cpuUnits)
        cpu = parsedCPU.value
        cpuUnit = parsedCPU.unit ?? ServerEditView.cpuUnits[0]
        let parsedMemory = parseValueUnit(server.memory, units: ServerEditView.memoryUnits)
        memory = parsedMemory.value
        memoryUnit = parsedMemory.unit ?? ServerEditView.memoryUnits[0]
        disk = server.disk
        credentials = server.credentials
        remark = server.remark
        loadedServerID = server.id
    }

    /// 把 "8C" / "32G" 拆成 (value: "8", unit: "C")；无单位串整体进 value
    private func parseValueUnit(_ text: String, units: [String]) -> (value: String, unit: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return ("", nil) }
        for unit in units {
            if trimmed.hasSuffix(unit), Int(trimmed.dropLast(unit.count)) != nil {
                return (String(trimmed.dropLast(unit.count)), unit)
            }
        }
        return (trimmed, nil)
    }

    /// 字段变化即写入 Store（空值不覆盖 hostname；至少保留一个非空 IP）
    private func saveIfLoaded() {
        guard loadedServerID == server.id else { return }
        guard var target = store.server(id: server.id) else { return }

        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHostname.isEmpty {
            target.hostname = trimmedHostname
        }
        let cleanedIPs = ips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleanedIPs.isEmpty {
            target.ips = cleanedIPs
        }
        target.os = os.trimmingCharacters(in: .whitespacesAndNewlines)
        let cpuNum = cpu.trimmingCharacters(in: .whitespaces)
        target.cpu = cpuNum.isEmpty ? "" : cpuNum + cpuUnit
        let memNum = memory.trimmingCharacters(in: .whitespaces)
        target.memory = memNum.isEmpty ? "" : memNum + memoryUnit
        target.disk = disk.trimmingCharacters(in: .whitespacesAndNewlines)
        // 凭据：过滤掉用户名与密码均为空的行
        target.credentials = credentials.filter { !$0.username.isEmpty || !$0.password.isEmpty }
        target.remark = remark
        store.upsertServer(target)
    }

}

/// 从服务库多选绑定到指定服务器
struct ServicePickerView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let server: Server

    @State private var keyword = ""
    @State private var selectedIDs: Set<Service.ID> = []

    private var candidates: [Service] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundIDs = Set(store.boundServices(of: server.id).map(\.id))
        let unbound = store.services.filter { !boundIDs.contains($0.id) }
        guard !query.isEmpty else { return unbound }
        let lower = query.lowercased()
        return unbound.filter {
            $0.name.lowercased().contains(lower)
                || $0.envs.contains { $0.lowercased().contains(lower) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("绑定服务到 \(server.hostname)")
                .font(.headline)
                .padding(.top, 14)

            List(selection: $selectedIDs) {
                ForEach(candidates) { service in
                    HStack {
                        Image(systemName: "shippingbox")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(service.name)
                            HStack(spacing: 4) {
                                ForEach(service.envs.sorted(), id: \.self) { env in
                                    Text(env.uppercased())
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
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
                        Spacer()
                    }
                    .tag(service.id)
                }
            }
            .listStyle(.inset)
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "没有可绑定的服务",
                        systemImage: "shippingbox",
                        description: Text("服务库中的服务都已绑定到本机，或先在左侧新增服务")
                    )
                }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索服务名 / 环境", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
            }

            Divider()

            HStack {
                Text("已选 \(selectedIDs.count) 个")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("绑定") {
                    store.bind(Array(selectedIDs), to: server.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 480, height: 520)
    }

    /// 环境配色：prod 红 / uat 橙 / sit 蓝 / 其他灰
}
