import SwiftUI

/// 工具栏「检查更新」按钮 + 新版提示与升级确认
/// 提示策略：仅「发现新版本」改变按钮形态（醒目徽标），其余结果一律静默——
/// 「已是最新/检查失败」不弹窗打扰（失败信息看按钮 help 气泡），手动检查也一样。
struct UpdateButton: View {
    @EnvironmentObject private var updateChecker: UpdateChecker
    @State private var isConfirming = false
    @State private var isShowingAppSettings = false

    var body: some View {
        Group {
            switch updateChecker.state {
            case .available(let version):
                // 有新版：高对比徽标按钮（白字橙底），点击弹升级确认
                Button {
                    isConfirming = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .orange)
                        Text("新版本 v\(version)")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("发现新版本 v\(version)，点击升级")
            case .checking:
                ProgressView()
                    .controlSize(.small)
                    .help("正在检查更新…")
            case .idle:
                // 未检查：普通工具栏图标
                Button {
                    Task { await updateChecker.checkForUpdates() }
                } label: {
                    Label("检查更新…", systemImage: "arrow.triangle.2.circlepath")
                }
                .focusEffectDisabled()
                .help("检查更新")
            case .upToDate:
                Button { } label: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                .disabled(true)
                .focusEffectDisabled()
                .help("已是最新版本（点击「检查更新」图标可重新检查）")
            case .failed(let reason):
                // 失败：可点击重试，原因看气泡；双击可直接进代理设置
                Button {
                    Task { await updateChecker.checkForUpdates() }
                } label: {
                    Image(systemName: "exclamationmark.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
                .focusEffectDisabled()
                .help("检查更新失败：\(reason)（点此重试）")
            }
        }
        .confirmationDialog(
            "升级到新版本？",
            isPresented: $isConfirming
        ) {
            Button("立即升级") { updateChecker.performUpgrade() }
            Button("稍后", role: .cancel) {}
        } message: {
            if case .available(let version) = updateChecker.state {
                Text("将退出 app，通过 Homebrew 升级到 v\(version) 并自动重启（未走 brew 安装时打开下载页）。")
            }
        }
        .contextMenu {
            if case .failed = updateChecker.state {
                Button {
                    isShowingAppSettings = true
                } label: {
                    Label("配置代理…", systemImage: "network")
                }
            }
        }
        .sheet(isPresented: $isShowingAppSettings) {
            AppSettingsView()
        }
    }
}
