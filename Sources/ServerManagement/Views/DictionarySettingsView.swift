import SwiftUI
import AppKit

/// 字典管理：环境（颜色）与操作系统，原地编辑

/// NSColorWell 的 SwiftUI 包装（CLT SDK 无 SwiftUI.ColorWell）
struct ColorWellView: NSViewRepresentable {
    @Binding var value: Color

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.color = NSColor(value)
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        if nsView.color != NSColor(value), !context.coordinator.isEditing {
            nsView.color = NSColor(value)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    final class Coordinator: NSObject {
        var value: Binding<Color>
        var isEditing = false

        init(value: Binding<Color>) {
            self.value = value
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            isEditing = true
            value.wrappedValue = Color(nsColor: sender.color)
            isEditing = false
        }
    }
}
struct DictionarySettingsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    private enum Tab: String, CaseIterable, Identifiable {
        case env = "环境"
        case os = "操作系统"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .env

    var body: some View {
        VStack(spacing: 0) {
            // 自定义分段头：选中项高亮下划线，无系统工具栏底边
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) { tab = item }
                    } label: {
                        VStack(spacing: 6) {
                            Text(item.rawValue)
                                .font(.headline)
                                .foregroundStyle(tab == item ? .primary : .secondary)
                            Rectangle()
                                .fill(tab == item ? Color.accentColor : .clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 32)
            .overlay(alignment: .bottom) {
                Divider()
            }

            Group {
                switch tab {
                case .env: EnvDictionaryView()
                case .os: OSDictionaryView()
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 470)
    }
}

// MARK: - 环境颜色选择（预设色板 + 自定义颜色井）

/// 预设环境色
private let envPresetColors: [(name: String, hex: String)] = [
    ("红", "#E5484D"),
    ("橙", "#F76B15"),
    ("黄", "#FFB224"),
    ("绿", "#30A46C"),
    ("蓝", "#0091FF"),
    ("紫", "#7C3AED"),
    ("粉", "#E93D82"),
    ("灰", "#8B8D98"),
]

/// 预设色板（含"默认"项）+ 自定义颜色井；选择结果通过 onPick 回调
private struct EnvColorPicker: View {
    /// 当前 hex；nil 表示未设置（用默认规则）
    let currentHex: String?
    let onPick: (String?) -> Void

    private var currentColor: Color {
        if let currentHex, let color = Color(hex: currentHex) { return color }
        return Color.gray
    }

    /// 当前选中是否命中预设
    private var matchedPreset: String? {
        envPresetColors.first { $0.hex.lowercased() == currentHex?.lowercased() }?.hex
    }

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Button("默认（按环境名自动）") { onPick(nil) }
                Divider()
                ForEach(envPresetColors, id: \.hex) { preset in
                    Button {
                        onPick(preset.hex)
                    } label: {
                        HStack {
                            Text(preset.name)
                            if matchedPreset == preset.hex {
                                Text("✓")
                            }
                        }
                    }
                }
                Divider()
                Button("自定义…") {
                    isCustomWellShown.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(currentColor)
                        .frame(width: 12, height: 12)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if isCustomWellShown {
                ColorWellView(value: Binding(
                    get: { currentColor },
                    set: { color in onPick(color.hexString) }
                ))
                .frame(width: 32)
            }
        }
    }

    @State private var isCustomWellShown = false
}

// MARK: - 环境字典

private struct EnvDictionaryView: View {
    @EnvironmentObject private var store: Store

    @State private var newName = ""
    @State private var newColorHex: String? = nil
    @State private var pendingDelete: EnvDefinition?
    @State private var editingID: EnvDefinition.ID?
    @State private var editingName = ""
    @State private var editingColorHex: String?
    @State private var duplicateHint = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.envDefinitions) { definition in
                    envRow(definition)
                }
            }
            .listStyle(.inset)

            // 底部固定添加区
            HStack(spacing: 8) {
                TextField("新环境名（如 gray）", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                EnvColorPicker(currentHex: newColorHex) { newColorHex = $0 }
                Button("添加", action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Text("删除环境不影响服务中已使用的旧值（颜色回退默认）；修改名称会同步更新所有引用")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .alert(
            "删除环境",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let target = pendingDelete { store.deleteEnv(target.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除字典项「\(pendingDelete?.name ?? "")」后，仍使用该环境的服务将回退默认颜色。")
        }
    }

    @ViewBuilder
    private func envRow(_ definition: EnvDefinition) -> some View {
        if editingID == definition.id {
            HStack(spacing: 8) {
                TextField("环境名", text: $editingName)
                    .onSubmit { commitRename(definition) }
                EnvColorPicker(currentHex: editingColorHex) { editingColorHex = $0 }
                Button("保存", action: { commitRename(definition) })
                Button("取消") {
                    editingID = nil
                    duplicateHint = false
                }
            }
        } else {
            HStack(spacing: 8) {
                Text(definition.name.uppercased())
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((definition.color ?? Color.defaultEnvColor(definition.name)).opacity(0.18), in: Capsule())
                    .foregroundStyle(definition.color ?? Color.defaultEnvColor(definition.name))

                Spacer()

                if duplicateHint && editingID == nil {
                    Text("名称重复").font(.caption2).foregroundStyle(.red)
                }

                EnvColorPicker(currentHex: definition.colorHex) { hex in
                    _ = store.updateEnv(definition.id, name: definition.name, colorHex: hex)
                }

                Button {
                    editingID = definition.id
                    editingName = definition.name
                    editingColorHex = definition.colorHex
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("重命名（同步所有引用）")

                Button(role: .destructive) {
                    pendingDelete = definition
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("删除该环境字典项")
            }
        }
    }

    private func commitRename(_ definition: EnvDefinition) {
        let ok = store.updateEnv(definition.id, name: editingName, colorHex: editingColorHex)
        if ok {
            editingID = nil
            editingName = ""
            duplicateHint = false
        } else {
            duplicateHint = true
        }
    }

    private func add() {
        guard store.addEnv(name: newName, colorHex: newColorHex) else { return }
        newName = ""
        newColorHex = nil
    }
}

// MARK: - 操作系统字典

private struct OSDictionaryView: View {
    @EnvironmentObject private var store: Store

    @State private var editingID: OSDefinition.ID?
    @State private var editingName = ""
    @State private var newName = ""
    @State private var pendingDelete: OSDefinition?
    @State private var duplicateHint = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.osDefinitions) { definition in
                    osRow(definition)
                }
            }
            .listStyle(.inset)

            // 底部固定添加区
            HStack(spacing: 8) {
                TextField("新系统名（如 Debian 12）", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("添加", action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Text("修改系统名会同步更新所有服务器的存量数据；删除不影响已使用的服务器")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .alert(
            "删除操作系统",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let target = pendingDelete { store.deleteOS(target.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除字典项「\(pendingDelete?.name ?? "")」后，仍使用该系统的服务器数据保持不变。")
        }
    }

    @ViewBuilder
    private func osRow(_ definition: OSDefinition) -> some View {
        if editingID == definition.id {
            HStack(spacing: 8) {
                TextField("系统名", text: $editingName)
                    .onSubmit { commitRename(definition) }
                Button("保存", action: { commitRename(definition) })
                Button("取消") {
                    editingID = nil
                    editingName = ""
                    duplicateHint = false
                }
            }
        } else {
            HStack(spacing: 8) {
                Text(definition.name)
                if duplicateHint && editingID == nil {
                    Text("名称重复").font(.caption2).foregroundStyle(.red)
                }
                Spacer()
                Button {
                    editingID = definition.id
                    editingName = definition.name
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("重命名（同步存量数据）")

                Button(role: .destructive) {
                    pendingDelete = definition
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("删除该系统字典项")
            }
        }
    }

    private func commitRename(_ definition: OSDefinition) {
        let ok = store.updateOS(definition.id, name: editingName)
        if ok {
            editingID = nil
            editingName = ""
            duplicateHint = false
        } else {
            duplicateHint = true
        }
    }

    private func add() {
        guard store.addOS(name: newName) else { return }
        newName = ""
    }
}
