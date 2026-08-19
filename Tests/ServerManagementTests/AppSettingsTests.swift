import Testing
@testable import ServerManagement

/// 代理配置解析
struct AppSettingsTests {

    @Test("解析：host:port 默认 http")
    func parseHostPort() {
        let p = ProxyConfig.parseProxy("127.0.0.1:7890")
        #expect(p?.scheme == .http)
        #expect(p?.host == "127.0.0.1")
        #expect(p?.port == 7890)
        #expect(p?.urlText == "http://127.0.0.1:7890")
    }

    @Test("解析：显式 scheme 与空白容错")
    func parseSchemes() {
        #expect(ProxyConfig.parseProxy("http://127.0.0.1:7890")?.scheme == .http)
        #expect(ProxyConfig.parseProxy("socks5://127.0.0.1:7891")?.scheme == .socks5)
        #expect(ProxyConfig.parseProxy("  localhost:1080  ")?.host == "localhost")
        #expect(ProxyConfig.parseProxy("SOCKS5://127.0.0.1:1080")?.scheme == .socks5)
    }

    @Test("解析：非法输入返回 nil")
    func parseInvalid() {
        #expect(ProxyConfig.parseProxy("") == nil)
        #expect(ProxyConfig.parseProxy("   ") == nil)
        #expect(ProxyConfig.parseProxy("abc") == nil)               // 无端口
        #expect(ProxyConfig.parseProxy("host:0") == nil)             // 端口越界
        #expect(ProxyConfig.parseProxy("host:99999") == nil)
        #expect(ProxyConfig.parseProxy("host:abc") == nil)
        #expect(ProxyConfig.parseProxy("http://:7890") == nil)       // 空 host
        #expect(ProxyConfig.parseProxy("ho'st:7890") == nil)         // 非法字符（防注入）
        #expect(ProxyConfig.parseProxy("host;rm -rf:7890") == nil)
    }

    @Test("connectionProxyDictionary：http 与 socks5 键完整")
    func proxyDictionary() {
        let http = ProxyConfig.parseProxy("127.0.0.1:7890")?.connectionProxyDictionary
        #expect(http?["HTTPSEnable"] as? Bool == true)
        #expect(http?["HTTPSProxy"] as? String == "127.0.0.1")
        #expect(http?["HTTPSPort"] as? Int == 7890)

        let socks = ProxyConfig.parseProxy("socks5://127.0.0.1:7891")?.connectionProxyDictionary
        #expect(socks?["SOCKSEnable"] as? Bool == true)
        #expect(socks?["SOCKSProxy"] as? String == "127.0.0.1")
        #expect(socks?["SOCKSPort"] as? Int == 7891)
    }
}
