import SwiftUI

/// 工具栏「检查更新」按钮 + 新版提示与升级确认
struct UpdateButton: View {
    @EnvironmentObject private var updateChecker: UpdateChecker
    @State private var isConfirming = false
    @State private var resultMessage: String?
    @State private var isShowingAppSettings = false

    var body: some View {
        Group {
            switch updateChecker.state {
            case .available(let version):
                // 有新版：醒目按钮，点击弹升级确认
                Button {
                    isConfirming = true
                } label: {
                    Label("升级到 v\(version)", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .focusEffectDisabled()
                .help("发现新版本 v\(version)，点击升级")
            case .checking:
                ProgressView()
                    .controlSize(.small)
                    .help("正在检查更新…")
            default:
                // 无新版/失败/未检查：手动入口收进菜单，避免打扰
                Button {
                    Task { await updateChecker.checkForUpdates() }
                } label: {
                    Label("检查更新…", systemImage: "arrow.triangle.2.circlepath")
                }
                .focusEffectDisabled()
                .help("检查更新")
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
        .onChange(of: updateChecker.state) { _, newState in
            // 手动检查的结果以 alert 反馈；静默检查到新版靠按钮自身提示，不打断
            switch newState {
            case .upToDate:
                resultMessage = "已是最新版本。"
            case .failed(let reason):
                resultMessage = "检查更新失败：\(reason)"
            default:
                resultMessage = nil
            }
        }
        .alert(
            "软件更新",
            isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })
        ) {
            // 网络类失败时提供代理配置入口（sheet 会继承 environmentObjects）
            if case .failed = updateChecker.state {
                Button("配置代理…") { isShowingAppSettings = true }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
        .sheet(isPresented: $isShowingAppSettings) {
            AppSettingsView()
        }
    }
}
