import SwiftUI

/// 网络代理设置（检查更新 / brew 升级共用）
struct AppSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：127.0.0.1:7890", text: $settings.proxyText)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("网络代理")
                } footer: {
                    footer
                }
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(width: 460, height: 240)
    }

    /// 输入实时反馈：空 = 直连；有效 = 走代理；无效 = 红字提示
    @ViewBuilder
    private var footer: some View {
        let trimmed = settings.proxyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Text("未配置：检查更新与升级直连（沿用系统默认网络）。")
        } else if let proxy = settings.proxy {
            Label("将使用代理 \(proxy.urlText)（检查更新与 brew 升级）。", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        } else {
            Label("格式无效，支持 host:port、http://host:port、socks5://host:port。", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}
