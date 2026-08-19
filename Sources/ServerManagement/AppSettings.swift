import Foundation
import CFNetwork
import Combine

/// 代理配置：解析与持久化。全部未配置 = 直连（系统默认）
/// - HTTP(S)：http:// 或裸 host:port，用于 API 请求与 brew 下载的 HTTP(S)_PROXY
/// - SOCKS5：socks5:// 或裸 host:port，用于 API 请求与 brew 下载的 ALL_PROXY
/// 两者可只填其一；混合端口（如 Clash 7890）填在 HTTP(S) 即可
final class AppSettings: ObservableObject {

    private static let httpProxyKey = "network.proxy.http"
    private static let socksProxyKey = "network.proxy.socks5"

    /// HTTP(S) 代理串（如 "127.0.0.1:7890"），空 = 未配置
    @Published var httpProxyText: String {
        didSet { UserDefaults.standard.set(httpProxyText, forKey: Self.httpProxyKey) }
    }

    /// SOCKS5 代理串（如 "127.0.0.1:7891" / "socks5://…"），空 = 未配置
    @Published var socksProxyText: String {
        didSet { UserDefaults.standard.set(socksProxyText, forKey: Self.socksProxyKey) }
    }

    /// 解析后的 HTTP(S) 代理；输入无效视为未配置
    var httpProxy: ProxyConfig? {
        ProxyConfig.parseProxy(httpProxyText, defaultScheme: .http)
    }

    /// 解析后的 SOCKS5 代理；输入无效视为未配置
    var socksProxy: ProxyConfig? {
        ProxyConfig.parseProxy(socksProxyText, defaultScheme: .socks5)
    }

    /// 是否配置了任一代理（决定检查更新的降级策略）
    var hasProxy: Bool {
        httpProxy != nil || socksProxy != nil
    }

    /// API 请求优先使用的代理：SOCKS5 优先（穿透性更好），未配则 HTTP(S)
    var preferredProxy: ProxyConfig? {
        socksProxy ?? httpProxy
    }

    init() {
        let defaults = UserDefaults.standard
        // 旧版单框 key 迁移：有旧值且新 HTTP 框为空时继承
        let legacy = defaults.string(forKey: "network.proxy") ?? ""
        httpProxyText = defaults.string(forKey: Self.httpProxyKey) ?? legacy
        socksProxyText = defaults.string(forKey: Self.socksProxyKey) ?? ""
    }
}

/// 代理配置值：scheme + host + port
struct ProxyConfig: Equatable {
    enum Scheme: String {
        case http
        case socks5
    }

    var scheme: Scheme
    var host: String
    var port: Int

    /// 代理完整 URL 文本（如 "http://127.0.0.1:7890"），用于展示与 curl 环境变量
    var urlText: String {
        "\(scheme.rawValue)://\(host):\(port)"
    }

    /// URLSession connectionProxyDictionary
    var connectionProxyDictionary: [String: Any] {
        switch scheme {
        case .http:
            return [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        case .socks5:
            return [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: host,
                kCFNetworkProxiesSOCKSPort as String: port,
            ]
        }
    }

    /// 解析代理串；支持 `host:port`（按 defaultScheme）、显式 `http://` / `socks5://`（`socks://` 视为别名，覆盖默认）
    /// host 仅允许字母/数字/点/横线/下划线（防 shell 注入），端口 1-65535；无效返回 nil
    static func parseProxy(_ text: String, defaultScheme: Scheme) -> ProxyConfig? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var rest = trimmed
        var scheme = defaultScheme
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") {
            scheme = .http
            rest = String(trimmed.dropFirst("http://".count))
        } else if lower.hasPrefix("socks5://") {
            scheme = .socks5
            rest = String(trimmed.dropFirst("socks5://".count))
        } else if lower.hasPrefix("socks://") {
            scheme = .socks5
            rest = String(trimmed.dropFirst("socks://".count))
        }

        guard let sep = rest.lastIndex(of: ":") else { return nil }
        let host = String(rest[..<sep])
        let portText = String(rest[rest.index(after: sep)...])
        guard !host.isEmpty,
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }),
              let port = Int(portText),
              (1...65535).contains(port)
        else { return nil }
        return ProxyConfig(scheme: scheme, host: host, port: port)
    }
}
