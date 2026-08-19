import Testing
@testable import ServerManagement

/// 代理配置解析（双框：HTTP(S) 默认 http、SOCKS5 默认 socks5）
struct AppSettingsTests {

    @Test("解析：host:port 按 defaultScheme 取 scheme")
    func parseHostPort() {
        let http = ProxyConfig.parseProxy("127.0.0.1:7890", defaultScheme: .http)
        #expect(http?.scheme == .http)
        #expect(http?.host == "127.0.0.1")
        #expect(http?.port == 7890)
        #expect(http?.urlText == "http://127.0.0.1:7890")

        let socks = ProxyConfig.parseProxy("127.0.0.1:7891", defaultScheme: .socks5)
        #expect(socks?.scheme == .socks5)
        #expect(socks?.urlText == "socks5://127.0.0.1:7891")
    }

    @Test("解析：显式 scheme 覆盖默认与空白容错")
    func parseSchemes() {
        #expect(ProxyConfig.parseProxy("http://127.0.0.1:7890", defaultScheme: .socks5)?.scheme == .http)
        #expect(ProxyConfig.parseProxy("socks5://127.0.0.1:7891", defaultScheme: .http)?.scheme == .socks5)
        #expect(ProxyConfig.parseProxy("socks://127.0.0.1:7891", defaultScheme: .http)?.scheme == .socks5)  // 别名
        #expect(ProxyConfig.parseProxy("  localhost:1080  ", defaultScheme: .http)?.host == "localhost")
        #expect(ProxyConfig.parseProxy("SOCKS5://127.0.0.1:1080", defaultScheme: .http)?.scheme == .socks5)
    }

    @Test("解析：非法输入返回 nil")
    func parseInvalid() {
        #expect(ProxyConfig.parseProxy("", defaultScheme: .http) == nil)
        #expect(ProxyConfig.parseProxy("   ", defaultScheme: .http) == nil)
        #expect(ProxyConfig.parseProxy("abc", defaultScheme: .http) == nil)               // 无端口
        #expect(ProxyConfig.parseProxy("host:0", defaultScheme: .http) == nil)             // 端口越界
        #expect(ProxyConfig.parseProxy("host:99999", defaultScheme: .http) == nil)
        #expect(ProxyConfig.parseProxy("host:abc", defaultScheme: .http) == nil)
        #expect(ProxyConfig.parseProxy("http://:7890", defaultScheme: .http) == nil)       // 空 host
        #expect(ProxyConfig.parseProxy("ho'st:7890", defaultScheme: .http) == nil)         // 非法字符（防注入）
        #expect(ProxyConfig.parseProxy("host;rm -rf:7890", defaultScheme: .http) == nil)
    }

    @Test("connectionProxyDictionary：http 与 socks5 键完整")
    func proxyDictionary() {
        let http = ProxyConfig.parseProxy("127.0.0.1:7890", defaultScheme: .http)?.connectionProxyDictionary
        #expect(http?["HTTPSEnable"] as? Bool == true)
        #expect(http?["HTTPSProxy"] as? String == "127.0.0.1")
        #expect(http?["HTTPSPort"] as? Int == 7890)

        let socks = ProxyConfig.parseProxy("socks5://127.0.0.1:7891", defaultScheme: .socks5)?.connectionProxyDictionary
        #expect(socks?["SOCKSEnable"] as? Bool == true)
        #expect(socks?["SOCKSProxy"] as? String == "127.0.0.1")
        #expect(socks?["SOCKSPort"] as? Int == 7891)
    }
}
