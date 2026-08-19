import Foundation
import CFNetwork
import Combine

/// 代理配置：解析与持久化。未配置 = 直连（系统默认）
final class AppSettings: ObservableObject {

    private static let proxyKey = "network.proxy"

    /// 用户输入的代理串（如 "127.0.0.1:7890" / "socks5://127.0.0.1:7891"），空 = 未配置
    @Published var proxyText: String {
        didSet { UserDefaults.standard.set(proxyText, forKey: Self.proxyKey) }
    }

    /// 解析后的有效代理；输入无效视为未配置（直连）
    var proxy: ProxyConfig? {
        ProxyConfig.parseProxy(proxyText)
    }

    init() {
        proxyText = UserDefaults.standard.string(forKey: Self.proxyKey) ?? ""
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

    /// 解析代理串；支持 `host:port`（默认 http）、`http://host:port`、`socks5://host:port`
    /// host 仅允许字母/数字/点/横线/下划线（防 shell 注入），端口 1-65535；无效返回 nil
    static func parseProxy(_ text: String) -> ProxyConfig? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var rest = trimmed
        var scheme = Scheme.http
        if trimmed.lowercased().hasPrefix("http://") {
            rest = String(trimmed.dropFirst("http://".count))
        } else if trimmed.lowercased().hasPrefix("socks5://") {
            scheme = .socks5
            rest = String(trimmed.dropFirst("socks5://".count))
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
