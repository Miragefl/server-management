import SwiftUI

/// 服务新增 / 编辑表单（独立实体 + 部署目标服务器多选）
struct ServiceEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    /// nil 表示新增
    let service: Service?

    @State private var name = ""
    @State private var selectedEnvs: Set<String> = []
    @State private var customEnvInput = ""
    @State private var ports: [ServicePort] = []
    @State private var installMethod = ""
    @State private var remark = ""

    /// 部署目标：新增=创建后绑定；编辑=调整绑定集合
    @State private var targetServerIDs: Set<Server.ID> = []
    @State private var serverKeyword = ""

    /// 已选环境（含自定义），按常见顺序优先展示
    private var orderedEnvs: [String] {
        let common = store.envDefinitions.map(\.name).filter { selectedEnvs.contains($0) }
        let extra = selectedEnvs.subtracting(store.envDefinitions.map(\.name)).sorted()
        return common + extra
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("服务信息") {
                    TextField("服务名 *（如 nginx、order-api）", text: $name)
                    envPicker
                    portsEditor
                    installMethodField
                }
                Section("备注") {
                    TextField("备注", text: $remark, axis: .vertical)
                        .lineLimit(2...4)
                }
                targetServerPicker
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(service == nil ? "添加" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isFormValid)
            }
            .padding(12)
        }
        .frame(width: 480, height: 700)
        .onAppear {
            if let service {
                name = service.name
                selectedEnvs = Set(service.envs)
                ports = service.ports
                installMethod = service.installMethod
                remark = service.remark
                targetServerIDs = Set(store.boundServers(of: service.id).map(\.id))
            }
        }
    }

    // MARK: - 环境多选

    /// 常见环境可点选 + 自定义环境可添加，已选环境以可删除标签展示
    private var envPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(store.envDefinitions.map(\.name), id: \.self) { env in
                    envChip(env, isSelected: selectedEnvs.contains(env)) {
                        toggleEnv(env)
                    }
                }
                Spacer()
            }
            if !orderedEnvs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(orderedEnvs, id: \.self) { env in
                        selectedEnvTag(env)
                    }
                    Spacer()
                }
            }
            HStack {
                TextField("添加自定义环境…", text: $customEnvInput)
                    .onSubmit(addCustomEnv)
                Button("添加", action: addCustomEnv)
                    .disabled(customEnvInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func envChip(_ env: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(env.uppercased())
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected ? store.color(for: env).opacity(0.25) : Color(nsColor: .controlBackgroundColor)
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? store.color(for: env) : Color.nsSeparator, lineWidth: 1)
                )
                .foregroundStyle(isSelected ? store.color(for: env) : .primary)
        }
        .buttonStyle(.plain)
    }

    private func selectedEnvTag(_ env: String) -> some View {
        HStack(spacing: 3) {
            Text(env.uppercased())
                .font(.caption.weight(.medium))
            Button {
                selectedEnvs.remove(env)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(store.color(for: env).opacity(0.15), in: Capsule())
        .foregroundStyle(store.color(for: env))
    }

    private func toggleEnv(_ env: String) {
        if selectedEnvs.contains(env) {
            selectedEnvs.remove(env)
        } else {
            selectedEnvs.insert(env)
        }
    }

    private func addCustomEnv() {
        let value = customEnvInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return }
        selectedEnvs.insert(value)
        customEnvInput = ""
    }


    // MARK: - 端口（多值 + 描述）

    private var portsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($ports) { $port in
                HStack(spacing: 8) {
                    TextField("端口", text: Binding(
                        get: { port.port > 0 ? String(port.port) : "" },
                        set: { port.port = Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                    ))
                    .monospacedDigit()
                    .frame(width: 70)
                    TextField("描述（可选）", text: $port.remark)
                    Button(role: .destructive) {
                        ports.removeAll { $0.id == port.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                ports.append(ServicePort(port: 0, remark: ""))
            } label: {
                Label("添加端口", systemImage: "plus.circle.dashed")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
        }
    }

    /// 安装方式输入框 + 常见方式快捷键
    private var installMethodField: some View {
        HStack {
            TextField("安装方式（docker / rpm / tar…）", text: $installMethod)
            Menu {
                ForEach(Service.commonInstallMethods, id: \.self) { candidate in
                    Button(candidate) { installMethod = candidate }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - 部署目标（多选）

    private var filteredServers: [Server] {
        let query = serverKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = store.servers.sorted { $0.hostname.localizedStandardCompare($1.hostname) == .orderedAscending }
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.hostname.lowercased().contains(query)
                || $0.ips.contains { $0.lowercased().contains(query) }
                || $0.os.lowercased().contains(query)
        }
    }

    private var targetServerPicker: some View {
        Section("部署到服务器（多选，已选 \(targetServerIDs.count) 台）") {
            TextField("过滤服务器", text: $serverKeyword)
            ForEach(filteredServers) { candidate in
                Button {
                    if targetServerIDs.contains(candidate.id) {
                        targetServerIDs.remove(candidate.id)
                    } else {
                        targetServerIDs.insert(candidate.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: targetServerIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(targetServerIDs.contains(candidate.id) ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(candidate.hostname)
                            Text(candidate.primaryIP)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 校验与保存

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !selectedEnvs.isEmpty
            && validPorts != nil
    }

    /// 所有已填端口合法（未填/空行跳过）；返回 nil 表示存在非法输入
    private var validPorts: [ServicePort]? {
        ports.allSatisfy { $0.port == 0 || (1...65535).contains($0.port) }
            ? ports.filter { $0.port > 0 }
            : nil
    }

    private func save() {
        guard let portValues = validPorts else { return }

        var target = service ?? Service(name: "", envs: [], ports: [])
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.envs = orderedEnvs
        target.ports = portValues
        target.installMethod = installMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        target.remark = remark
        store.upsertService(target)

        // 同步部署目标：勾选的绑定，取消的解绑
        let desired = targetServerIDs
        let current = Set(store.boundServers(of: target.id).map(\.id))
        for serverID in desired where !current.contains(serverID) {
            store.bind([target.id], to: serverID)
        }
        for serverID in current where !desired.contains(serverID) {
            if let deployment = store.binding(serverID: serverID, serviceID: target.id) {
                store.unbind(deployment)
            }
        }
        dismiss()
    }
}

private extension Color {
    /// 系统分隔线颜色
    static var nsSeparator: Color {
        Color(nsColor: .separatorColor)
    }
}
