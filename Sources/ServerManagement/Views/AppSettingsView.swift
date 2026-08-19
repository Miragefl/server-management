import SwiftUI

/// 网络代理设置（检查更新 / brew 升级共用）
struct AppSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：127.0.0.1:7890", text: $settings.httpProxyText)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    statusIcon(settings.httpProxyText, parsed: settings.httpProxy)
                } header: {
                    Text("HTTP(S) 代理")
                } footer: {
                    if settings.httpProxyText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("用于 API 检查与 brew 下载。混合端口的代理填这里即可。")
                    }
                }

                Section {
                    TextField("例如：socks5://127.0.0.1:7891", text: $settings.socksProxyText)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    statusIcon(settings.socksProxyText, parsed: settings.socksProxy)
                } header: {
                    Text("SOCKS5 代理")
                } footer: {
                    if settings.socksProxyText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("可选；配置后 API 检查优先走 SOCKS5。")
                    }
                }

                Section {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("两框均可独立配置；都留空则全部直连。host:port、http://、socks5:// 格式均可。")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("网络代理")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(width: 460, height: 380)
    }

    /// 单框状态行：空 = 灰色「未启用」；有效 = 绿 ✓ + 代理串；无效 = 橙色格式提示
    @ViewBuilder
    private func statusIcon(_ text: String, parsed: ProxyConfig?) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Label("未启用", systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        } else if let proxy = parsed {
            Label(proxy.urlText, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        } else {
            Label("格式无效（支持 host:port / http:// / socks5://）", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    /// 底部汇总：当前生效的网络策略
    private var summary: String {
        switch (settings.httpProxy, settings.socksProxy) {
        case (nil, nil):
            return "当前：直连（未配置代理）。"
        case (let http, let socks):
            var parts: [String] = []
            if let http { parts.append("HTTP(S) \(http.urlText)") }
            if let socks { parts.append("SOCKS5 \(socks.urlText)") }
            return "当前：\(parts.joined(separator: "；"))，API 检查优先 SOCKS5，失败自动降级直连。"
        }
    }
}
