import SwiftUI

/// 右栏：服务详情（信息头原地编辑 + 端口列表 + 部署服务器表格）
struct ServiceDetailView: View {
    @EnvironmentObject private var store: Store
    let service: Service

    @State private var name = ""
    @State private var selectedEnvs: Set<String> = []
    @State private var customEnvInput = ""
    @State private var ports: [ServicePort] = []
    @State private var installMethod = ""
    @State private var credentials: [Credential] = []
    @State private var remark = ""
    @State private var loadedServiceID: Service.ID?

    @State private var servicePendingDelete = false
    @State private var serverPendingUnbind: Server?
    @State private var showCustomEnvPopover = false
    @State private var isPickingServers = false

    private var boundServers: [Server] {
        store.boundServers(of: service.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            infoHeader

            Divider()

            portsSection

            Divider()

            credentialsSection

            Divider()

            serverToolbar

            serverTable
        }
        .sheet(isPresented: $isPickingServers) {
            ServerPickerView(service: currentService).environmentObject(store)
        }
        .alert(
            "删除服务",
            isPresented: $servicePendingDelete
        ) {
            Button("删除", role: .destructive) {
                store.deleteService(currentService)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除服务「\(service.name)」并解除其与 \(store.bindingCount(of: service.id)) 台服务器的绑定，此操作不可撤销。")
        }
        .alert(
            "解除绑定",
            isPresented: Binding(
                get: { serverPendingUnbind != nil },
                set: { if !$0 { serverPendingUnbind = nil } }
            )
        ) {
            Button("解绑", role: .destructive) {
                if let server = serverPendingUnbind,
                   let deployment = store.binding(serverID: server.id, serviceID: service.id) {
                    store.unbind(deployment)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将「\(service.name)」从 \(serverPendingUnbind?.hostname ?? "") 上解绑。服务器记录保留，可随时重新绑定。")
        }
    }

    /// 当前 Store 里的最新服务数据（正被原地编辑更新）
    private var currentService: Service {
        store.service(id: service.id) ?? service
    }

    // MARK: - 信息头（原地编辑）

    private var infoHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    TextField("服务名", text: $name)
                        .font(.title2.bold())
                        .fixedSize()
                        .textFieldStyle(.plain)
                        .onChange(of: name) { _, _ in saveIfLoaded() }
                    Button(role: .destructive) {
                        servicePendingDelete = true
                    } label: {
                        Label("删除", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("删除服务（解除所有绑定）")
                }

                HStack(spacing: 10) {
                    envChips
                    installTag
                }

                groupTag

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
        .onChange(of: service.id) { _, _ in load() }
    }

    /// 环境胶囊：点选切换（至少保留一个）+ 自定义添加
    private var envChips: some View {
        HStack(spacing: 4) {
            ForEach(store.envDefinitions.map(\.name), id: \.self) { env in
                chip(env, isSelected: selectedEnvs.contains(env)) {
                    toggleEnv(env)
                }
            }
            ForEach(selectedEnvs.subtracting(store.envDefinitions.map(\.name)).sorted(), id: \.self) { env in
                chip(env, isSelected: true) { toggleEnv(env) }
            }
            Menu {
                Button("添加自定义环境…") { showCustomEnvPopover = true }
                if !selectedEnvs.subtracting(store.envDefinitions.map(\.name)).isEmpty {
                    Divider()
                    ForEach(selectedEnvs.subtracting(store.envDefinitions.map(\.name)).sorted(), id: \.self) { env in
                        Button("移除 \(env)") { selectedEnvs.remove(env); saveIfLoaded() }
                    }
                }
            } label: {
                Image(systemName: "plus.circle.dashed")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .popover(isPresented: $showCustomEnvPopover, arrowEdge: .bottom) {
                customEnvPopover
            }
        }
    }

    private var customEnvPopover: some View {
        HStack(spacing: 8) {
            TextField("自定义环境（如 gray）", text: $customEnvInput)
                .onSubmit(addCustomEnv)
            Button("添加", action: addCustomEnv)
                .disabled(customEnvInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
        .frame(width: 220)
    }

    private func addCustomEnv() {
        let value = customEnvInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return }
        selectedEnvs.insert(value)
        customEnvInput = ""
        showCustomEnvPopover = false
        saveIfLoaded()
    }

    private func chip(_ env: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(env.uppercased())
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(store.color(for: env).opacity(isSelected ? 0.18 : 0.04), in: Capsule())
                .foregroundStyle(isSelected ? store.color(for: env) : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func toggleEnv(_ env: String) {
        let before = selectedEnvs
        if selectedEnvs.contains(env) {
            selectedEnvs.remove(env)
        } else {
            selectedEnvs.insert(env)
        }
        // 至少保留一个环境
        if selectedEnvs.isEmpty {
            selectedEnvs = before
            return
        }
        saveIfLoaded()
    }

    /// 安装方式：inline 编辑 + 常用方式下拉（紧贴输入内容）
    /// （macOS 15+ borderlessButton Menu 自带下拉箭头，勿再放自定义箭头图标）
    private var installTag: some View {
        HStack(spacing: 2) {
            Text("安装").foregroundStyle(.secondary)
            TextField("—", text: $installMethod)
                .fixedSize()
                .font(.system(.callout, design: .monospaced))
                .textFieldStyle(.plain)
                .onChange(of: installMethod) { _, _ in saveIfLoaded() }
            Menu {
                ForEach(Service.commonInstallMethods, id: \.self) { candidate in
                    Button(candidate) { installMethod = candidate }
                }
                if !installMethod.isEmpty {
                    Divider()
                    Button("清空") { installMethod = "" }
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
                Text(currentService.group.isEmpty ? "—" : currentService.group)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(currentService.group.isEmpty ? 0 : 0.14), in: Capsule())
                    .foregroundStyle(currentService.group.isEmpty ? .secondary : Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.callout)
        .help("切换分组（字典在「环境 / 系统 / 分组」设置中维护）")
    }

    private func setGroup(_ name: String) {
        var target = currentService
        target.group = name
        store.upsertService(target)
    }

    // MARK: - 端口区（多值 + 描述）

    private var portsSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("端口（\(ports.count)）")
                .font(.headline)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 6) {
                ForEach($ports) { $port in
                    portRow($port)
                }
                if ports.isEmpty {
                    Text("未配置端口")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }

                Button {
                    ports.append(ServicePort(port: 0, remark: ""))
                } label: {
                    Label("添加端口", systemImage: "plus.circle.dashed")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            }
            .padding(.trailing, 16)

            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func portRow(_ port: Binding<ServicePort>) -> some View {
        HStack(spacing: 8) {
            TextField("端口", text: Binding(
                get: { port.wrappedValue.port > 0 ? String(port.wrappedValue.port) : "" },
                set: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    port.wrappedValue.port = Int(trimmed) ?? 0
                    saveIfLoaded()
                }
            ))
            .monospacedDigit()
            .frame(width: 64)
            .textFieldStyle(.roundedBorder)

            TextField("描述（可选，如 HTTP API）", text: Binding(
                get: { port.wrappedValue.remark },
                set: { text in
                    port.wrappedValue.remark = text
                    saveIfLoaded()
                }
            ))
            .font(.callout)
            .textFieldStyle(.roundedBorder)

            if port.wrappedValue.port != 0 && !isPortValid(port.wrappedValue.port) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("端口必须是 1-65535 的整数，当前输入未保存")
            }

            Button(role: .destructive) {
                ports.removeAll { $0.id == port.wrappedValue.id }
                saveIfLoaded()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .help("移除此端口")
        }
    }

    private func isPortValid(_ value: Int) -> Bool {
        (1...65535).contains(value)
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

    // MARK: - 部署服务器表格

    private var serverToolbar: some View {
        HStack {
            Text("部署服务器（\(boundServers.count)）")
                .font(.headline)
            Button {
                isPickingServers = true
            } label: {
                Label("绑定服务器", systemImage: "link")
            }
            .buttonStyle(.borderless)
            .help("多选服务器部署本服务")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var serverTable: some View {
        Table(boundServers) {
            TableColumn("Hostname") { server in
                HStack(spacing: 8) {
                    Text(server.hostname)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(server.hostname)
                    Spacer(minLength: 0)
                    Button(role: .destructive) {
                        serverPendingUnbind = server
                    } label: {
                        Text("解绑")
                    }
                    .font(.callout)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("从本服务解绑（服务器保留）")
                }
            }
            .width(min: 150, ideal: 190)
            TableColumn("IP") { server in
                Text(server.ipsSummary.isEmpty ? "—" : server.ipsSummary).monospaced()
            }
            .width(min: 110, ideal: 130)
            TableColumn("系统") { server in
                if server.os.isEmpty {
                    Text("—").foregroundStyle(.tertiary)
                } else {
                    Text(server.os)
                }
            }
            TableColumn("备注") { server in
                Text(server.remark)
                    .foregroundStyle(server.remark.isEmpty ? .tertiary : .primary)
            }
        }
        .overlay {
            if boundServers.isEmpty {
                ContentUnavailableView(
                    "未部署到任何服务器",
                    systemImage: "server.rack",
                    description: Text("点击右上角「绑定服务器」选择目标机器")
                )
            }
        }
    }

    // MARK: - 加载与即时保存

    private func load() {
        name = service.name
        selectedEnvs = Set(service.envs)
        ports = service.ports
        installMethod = service.installMethod
        credentials = service.credentials
        remark = service.remark
        loadedServiceID = service.id
    }

    /// 字段变化即写入 Store（未完成加载前不触发；非法端口行跳过不保存）
    private func saveIfLoaded() {
        guard loadedServiceID == service.id else { return }
        guard var target = store.service(id: service.id) else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            target.name = trimmedName
        }
        target.envs = orderedEnvs
        // 只保存合法端口行
        target.ports = ports.filter { isPortValid($0.port) }
        target.installMethod = installMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        // 凭据：过滤掉用户名与密码均为空的行
        target.credentials = credentials.filter { !$0.username.isEmpty || !$0.password.isEmpty }
        target.remark = remark
        store.upsertService(target)
    }

    private var orderedEnvs: [String] {
        let common = store.envDefinitions.map(\.name).filter { selectedEnvs.contains($0) }
        let extra = selectedEnvs.subtracting(store.envDefinitions.map(\.name)).sorted()
        return common + extra
    }

}

/// 为服务多选绑定服务器（复用服务侧视角）
struct ServerPickerView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let service: Service

    @State private var keyword = ""
    @State private var selectedIDs: Set<Server.ID> = []

    private var candidates: [Server] {
        let boundIDs = Set(store.boundServers(of: service.id).map(\.id))
        let unbound = store.servers.filter { !boundIDs.contains($0.id) }
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return unbound }
        let lower = query.lowercased()
        return unbound.filter {
            $0.hostname.lowercased().contains(lower)
                || $0.ips.contains { $0.lowercased().contains(lower) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("部署「\(service.name)」到服务器")
                .font(.headline)
                .padding(.top, 14)

            List(selection: $selectedIDs) {
                ForEach(candidates) { server in
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(server.hostname)
                            Text(server.primaryIP)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !server.os.isEmpty {
                            Text(server.os)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tag(server.id)
                }
            }
            .listStyle(.inset)
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "没有可绑定的服务器",
                        systemImage: "server.rack",
                        description: Text("所有服务器都已绑定本服务，或先在左侧新增服务器")
                    )
                }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索 hostname / IP", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
            }

            Divider()

            HStack {
                Text("已选 \(selectedIDs.count) 台")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("绑定") {
                    for serverID in selectedIDs {
                        store.bind([service.id], to: serverID)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 480, height: 520)
    }
}
