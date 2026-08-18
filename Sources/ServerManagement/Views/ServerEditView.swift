import SwiftUI
import AppKit

/// 服务器新增 / 编辑表单（多 IP + 硬件信息）
struct ServerEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    /// nil 表示新增
    let server: Server?

    @State private var hostname = ""
    @State private var ips: [String] = [""]
    @State private var os = ""
    @State private var cpuValue = ""
    @State private var cpuUnit = "C"
    @State private var memoryValue = ""
    @State private var memoryUnit = "G"
    @State private var diskText = ""
    @State private var remark = ""

    /// 常用硬件单位
    static let cpuUnits = ["C", "核"]
    static let memoryUnits = ["G", "T", "M"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("基本信息") {
                    TextField("Hostname", text: $hostname, prompt: Text("必填").foregroundColor(.secondary))
                    ipsEditor
                    osField
                }
                Section("硬件信息（可选）") {
                    cpuRow
                    memoryRow
                    diskRow
                }
                Section("备注") {
                    TextField("备注", text: $remark, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(server == nil ? "添加" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isFormValid)
            }
            .padding(12)
        }
        .frame(width: 460, height: 520)
        .onAppear(perform: load)
    }

    // MARK: - 多 IP

    private var ipsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ips.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    TextField(index == 0 ? "IP（主，必填）" : "IP", text: Binding(
                        get: { ips[index] },
                        set: { ips[index] = $0 }
                    ))
                    .overlay(alignment: .trailing) {
                        Button {
                            ips[index] = NSPasteboard.general.string(forType: .string) ?? ""
                        } label: {
                            Label("粘贴", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .padding(.trailing, 6)
                    }
                    if ips.count > 1 {
                        Button(role: .destructive) {
                            ips.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                ips.append("")
            } label: {
                Label("添加 IP", systemImage: "plus.circle.dashed")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - 硬件信息（标签左、输入右，与系统行布局一致）

    private var cpuRow: some View {
        HStack {
            Text("CPU")
            Spacer(minLength: 12)
            TextField("", text: $cpuValue, prompt: Text("8").foregroundColor(.secondary))
                .frame(width: 90)
                .monospacedDigit()
            Picker("", selection: $cpuUnit) {
                ForEach(Self.cpuUnits, id: \.self) { Text($0) }
            }
            .labelsHidden()
            .frame(width: 64)
        }
    }

    private var memoryRow: some View {
        HStack {
            Text("内存")
            Spacer(minLength: 12)
            TextField("", text: $memoryValue, prompt: Text("32").foregroundColor(.secondary))
                .frame(width: 90)
                .monospacedDigit()
            Picker("", selection: $memoryUnit) {
                ForEach(Self.memoryUnits, id: \.self) { Text($0) }
            }
            .labelsHidden()
            .frame(width: 64)
        }
    }

    private var diskRow: some View {
        HStack {
            Text("硬盘")
            Spacer(minLength: 12)
            TextField("", text: $diskText, prompt: Text("如 500G SSD + 2T HDD").foregroundColor(.secondary))
                .frame(maxWidth: 240, alignment: .trailing)
        }
    }

    // MARK: - 系统

    /// 操作系统输入框 + 常用系统快捷选择（可自由输入其他值）
    private var osField: some View {
        HStack {
            TextField("操作系统", text: $os, prompt: Text("如 Ubuntu 24.04").foregroundColor(.secondary))
            Menu {
                ForEach(store.osDefinitions) { candidate in
                    Button(candidate.name) { os = candidate.name }
                }
                if !os.isEmpty {
                    Divider()
                    Button("清空") { os = "" }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - 校验与保存

    private var isFormValid: Bool {
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty
            && !cleanedIPs.isEmpty
    }

    private var cleanedIPs: [String] {
        ips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func load() {
        guard let server else {
            ips = [""]
            return
        }
        hostname = server.hostname
        ips = server.ips.isEmpty ? [""] : server.ips
        os = server.os
        // 解析详情页自由格式：数字 + 单位（如 "8C"、"32G"）；无单位原样保留在数值框
        let parsedCPU = parseValueUnit(server.cpu, units: Self.cpuUnits)
        cpuValue = parsedCPU.value
        cpuUnit = parsedCPU.unit ?? Self.cpuUnits[0]
        let parsedMemory = parseValueUnit(server.memory, units: Self.memoryUnits)
        memoryValue = parsedMemory.value
        memoryUnit = parsedMemory.unit ?? Self.memoryUnits[0]
        diskText = server.disk
        remark = server.remark
    }

    /// 把 "8C" / "32G" 拆成 (value: "8", unit: "C")；复杂串（如 "2×8C"）整体进 value
    private func parseValueUnit(_ text: String, units: [String]) -> (value: String, unit: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return ("", nil) }
        for unit in units {
            if trimmed.hasSuffix(unit), let value = Int(trimmed.dropLast(unit.count)) {
                return (String(value), unit)
            }
        }
        return (trimmed, nil)
    }

    private func save() {
        var target = server ?? Server(hostname: "", ips: [])
        target.hostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        target.ips = cleanedIPs
        target.os = os.trimmingCharacters(in: .whitespacesAndNewlines)

        let cpuNum = cpuValue.trimmingCharacters(in: .whitespaces)
        target.cpu = cpuNum.isEmpty ? "" : cpuNum + cpuUnit
        let memNum = memoryValue.trimmingCharacters(in: .whitespaces)
        target.memory = memNum.isEmpty ? "" : memNum + memoryUnit
        target.disk = diskText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.remark = remark
        store.upsertServer(target)
        dismiss()
    }
}
