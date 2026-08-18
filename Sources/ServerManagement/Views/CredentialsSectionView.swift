import SwiftUI
import AppKit

/// 凭据编辑区（多行：用途 / 用户名 / 密码），供服务器与服务详情页复用
struct CredentialsSectionView: View {
    @Binding var credentials: [Credential]
    /// 凭据变化回调（由宿主写回 Store）
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($credentials) { $credential in
                CredentialRowView(credential: $credential, onCommit: onCommit) {
                    credentials.removeAll { $0.id == credential.id }
                    onCommit()
                }
            }
            if credentials.isEmpty {
                Text("未记录账号")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            Button {
                credentials.append(Credential(username: "", password: ""))
                onCommit()
            } label: {
                Label("添加账号", systemImage: "plus.circle.dashed")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// 单条凭据行：用途 + 用户名（可复制）+ 密码（默认掩码，可显隐/复制）
private struct CredentialRowView: View {
    @Binding var credential: Credential
    let onCommit: () -> Void
    let onDelete: () -> Void

    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            // 用途备注
            TextField("用途", text: $credential.remark, prompt: Text("如 root / 管理后台").foregroundColor(.secondary))
                .frame(width: 120)
                .textFieldStyle(.roundedBorder)
                .onChange(of: credential.remark) { _, _ in onCommit() }

            // 用户名
            HStack(spacing: 2) {
                TextField("用户名", text: $credential.username, prompt: Text("username").foregroundColor(.secondary))
                    .frame(width: 110)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: credential.username) { _, _ in onCommit() }
                copyButton(credential.username, help: "复制用户名")
            }

            // 密码（默认掩码，眼睛切换显隐）
            HStack(spacing: 2) {
                passwordField
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(revealed ? "隐藏密码" : "显示密码")
                .focusEffectDisabled()

                copyButton(credential.password, help: "复制密码")
            }

            Spacer(minLength: 4)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .help("删除该账号")
        }
    }

    @ViewBuilder
    private var passwordField: some View {
        if revealed {
            TextField("密码", text: $credential.password, prompt: Text("password").foregroundColor(.secondary))
                .frame(width: 130)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: credential.password) { _, _ in onCommit() }
        } else {
            SecureField("密码", text: $credential.password, prompt: Text("password").foregroundColor(.secondary))
                .frame(width: 130)
                .textFieldStyle(.roundedBorder)
                .onChange(of: credential.password) { _, _ in onCommit() }
        }
    }

    private func copyButton(_ text: String, help: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .disabled(text.isEmpty)
        .help(help)
        .focusEffectDisabled()
    }
}
