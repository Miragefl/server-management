import SwiftUI

/// 批量导入服务器：区间表达式展开 + OS 统一设定；导入后展示结果摘要
struct ServerImportView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var hostnameText = ""
    @State private var ipText = ""
    @State private var os = ""
    @State private var cpuValue = ""
    @State private var cpuUnit = ServerEditView.cpuUnits[0]
    @State private var memoryValue = ""
    @State private var memoryUnit = ServerEditView.memoryUnits[0]
    @State private var diskText = ""

    /// 导入结果（非 nil 时展示摘要页）
    @State private var addedCount = 0
    @State private var skippedServers: [Server] = []
    @State private var failedSegments: [String] = []
    @State private var isDone = false

    private var hostResult: ServerRangeParser.Result {
        ServerRangeParser.expand(hostnameText)
    }

    private var ipResult: ServerRangeParser.Result {
        ServerRangeParser.expand(ipText)
    }

    private var isReadyToImport: Bool {
        !hostResult.values.isEmpty
            && hostResult.values.count == ipResult.values.count
    }

    var body: some View {
        Group {
            if isDone {
                resultView
            } else {
                formView
            }
        }
        .frame(width: 560, height: 560)
    }

    // MARK: - 表单

    private var formView: some View {
        VStack(spacing: 0) {
            Form {
                Section("区间表达式（逗号分隔，~ 表示递增区间）") {
                    TextField("hostname，如 yd-vm121~125,yd-vm131~134", text: $hostnameText, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                    TextField("IP，如 10.137.32.121~125,10.137.32.131~134", text: $ipText, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
                Section("统一配置（可选）") {
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
                    hardwareSection
                }
                previewSection
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("导入") { importServers() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isReadyToImport)
            }
            .padding(12)
        }
    }

    // MARK: - 硬件信息（与 ServerEditView 布局一致）

    private var hardwareSection: some View {
        Group {
            HStack {
                Text("CPU")
                Spacer(minLength: 12)
                TextField("", text: $cpuValue, prompt: Text("8").foregroundColor(.secondary))
                    .frame(width: 90)
                    .monospacedDigit()
                Picker("", selection: $cpuUnit) {
                    ForEach(ServerEditView.cpuUnits, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .frame(width: 64)
            }
            HStack {
                Text("内存")
                Spacer(minLength: 12)
                TextField("", text: $memoryValue, prompt: Text("32").foregroundColor(.secondary))
                    .frame(width: 90)
                    .monospacedDigit()
                Picker("", selection: $memoryUnit) {
                    ForEach(ServerEditView.memoryUnits, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .frame(width: 64)
            }
            HStack {
                Text("硬盘")
                Spacer(minLength: 12)
                TextField("", text: $diskText, prompt: Text("如 500G SSD + 2T HDD").foregroundColor(.secondary))
                    .frame(maxWidth: 240, alignment: .trailing)
            }
        }
    }

    // MARK: - 预览

    @ViewBuilder
    private var previewSection: some View {
        Section("预览") {
            if hostnameText.isEmpty && ipText.isEmpty {
                Text("输入表达式后这里展示将生成的服务器")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let allFailed = hostResult.failedSegments.map { "hostname：\($0)" }
                    + ipResult.failedSegments.map { "IP：\($0)" }
                if !allFailed.isEmpty {
                    Label("非法段（将跳过）：" + allFailed.joined(separator: "、"), systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if hostResult.values.count != ipResult.values.count {
                    Label("hostname 展开数（\(hostResult.values.count)）与 IP 展开数（\(ipResult.values.count)）不一致，需相等后才能导入", systemImage: "xmark.circle")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else if !hostResult.values.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("将生成 \(hostResult.values.count) 台：")
                            .font(.callout.weight(.medium))
                        let configSummary = hardwareSummary
                        ForEach(previewPairs.prefix(8), id: \.0) { pair in
                            Text("\(pair.0)  \(pair.1)\(configSummary.isEmpty ? "" : "  ·  \(configSummary)")")
                                .font(.system(.callout, design: .monospaced))
                        }
                        if previewPairs.count > 8 {
                            Text("… 及其余 \(previewPairs.count - 8) 台")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var previewPairs: [(String, String)] {
        Array(zip(hostResult.values, ipResult.values))
    }

    /// 统一配置摘要（OS + 硬件），空项自动跳过
    private var hardwareSummary: String {
        var parts: [String] = []
        if !os.isEmpty { parts.append(os) }
        let cpuNum = cpuValue.trimmingCharacters(in: .whitespaces)
        if !cpuNum.isEmpty { parts.append(cpuNum + cpuUnit) }
        let memNum = memoryValue.trimmingCharacters(in: .whitespaces)
        if !memNum.isEmpty { parts.append(memNum + memoryUnit) }
        let disk = diskText.trimmingCharacters(in: .whitespaces)
        if !disk.isEmpty { parts.append(disk) }
        return parts.joined(separator: " / ")
    }

    // MARK: - 导入与结果

    private func importServers() {
        let cpuNum = cpuValue.trimmingCharacters(in: .whitespaces)
        let cpu = cpuNum.isEmpty ? "" : cpuNum + cpuUnit
        let memNum = memoryValue.trimmingCharacters(in: .whitespaces)
        let memory = memNum.isEmpty ? "" : memNum + memoryUnit
        let candidates = previewPairs.map { pair in
            Server(
                hostname: pair.0,
                ips: [pair.1],
                os: os,
                cpu: cpu,
                memory: memory,
                disk: diskText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let outcome = store.addServers(candidates)
        addedCount = outcome.added.count
        skippedServers = outcome.skipped
        failedSegments = hostResult.failedSegments.map { "hostname：\($0)" }
            + ipResult.failedSegments.map { "IP：\($0)" }
        isDone = true
    }

    private var resultView: some View {
        VStack(spacing: 16) {
            Image(systemName: addedCount > 0 ? "checkmark.circle.fill" : "info.circle")
                .font(.system(size: 44))
                .foregroundStyle(addedCount > 0 ? Color.green : .secondary)

            Text("成功导入 \(addedCount) 台服务器").font(.title3.bold())

            if !skippedServers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("跳过 \(skippedServers.count) 台（hostname 或 IP 与现有重复）：")
                        .font(.callout.weight(.medium))
                    ForEach(skippedServers.prefix(10)) { server in
                        Text("\(server.hostname)  \(server.primaryIP)")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    if skippedServers.count > 10 {
                        Text("… 及其余 \(skippedServers.count - 10) 台")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !failedSegments.isEmpty {
                Text("非法段未导入：" + failedSegments.joined(separator: "、"))
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
