import Foundation
import Combine
import AppKit

/// 版本号比较与 GitHub Release 检查 + brew 升级执行
/// 
/// 升级链路（brew 安装时）：
/// 退出 app → detached 脚本执行 brew upgrade --cask → xattr 去隔离 → open 重启
/// 非 brew 安装时降级为打开 Release 页面手动下载
/// 配置了代理（AppSettings）时：检查请求与 brew 升级均走代理，否则直连
final class UpdateChecker: ObservableObject {

    /// 检查/升级状态
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        /// 有新版，关联最新版本号（如 "0.4.0"）
        case available(version: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// 正在执行升级（app 即将退出）
    @Published private(set) var isUpgrading = false

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    private static let owner = "Miragefl"
    private static let repo = "server-management"
    private static let caskName = "server-management"
    private static let appName = "ServerManagement"

    /// 当前 app 版本；读不到（如 swift run 开发模式）返回 nil
    static var currentVersion: String? {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let v, !v.isEmpty, v != "1.0" else { return nil }
        return v
    }

    /// 语义化版本比较：lhs > rhs 返回 true（"0.10.0" > "0.9.1"）
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let l = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let r = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(l.count, r.count)
        for i in 0..<n {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// 检查 GitHub 最新 Release（去 tag 前缀 v）
    /// 走 github.com 网页通道（releases/latest 的 302 Location），不受 api.github.com 匿名限流（60 次/时/IP）影响；
    /// 配置了代理先走代理（SOCKS5 优先，未配用 HTTP(S)），失败自动降级直连重试。
    /// brew 升级下载仍走代理（大文件直连易被重置）。
    @MainActor
    func checkForUpdates() async {
        guard let current = Self.currentVersion else {
            state = .failed("开发模式（无版本信息），请从 Release 安装后使用自动升级")
            return
        }
        state = .checking
        do {
            let latest = try await fetchLatestTag(viaProxy: settings.hasProxy)
            state = Self.isVersion(latest, newerThan: current)
                ? .available(version: latest)
                : .upToDate
        } catch {
            guard settings.hasProxy else {
                state = .failed(Self.describe(error))
                return
            }
            // 代理失败 → 直连兜底；直连也失败才报双路错误
            let proxyError = error
            do {
                let latest = try await fetchLatestTag(viaProxy: false)
                state = Self.isVersion(latest, newerThan: current)
                    ? .available(version: latest)
                    : .upToDate
            } catch {
                state = .failed("代理检查失败：\(Self.describe(proxyError))；直连也失败：\(Self.describe(error))")
            }
        }
    }

    /// 请求 releases/latest（不跟随重定向），从 302 Location 提取 tag（如 "…/tag/v0.3.2" → "0.3.2"）
    /// URLSession 默认跟随重定向（会拿到 200 的 tag 页），须用 delegate 拦截才能拿到 302
    private func fetchLatestTag(viaProxy: Bool) async throws -> String {
        var req = URLRequest(url: URL(string: "https://github.com/\(Self.owner)/\(Self.repo)/releases/latest")!)
        req.timeoutInterval = 10
        let cfg = URLSessionConfiguration.default
        if viaProxy, let proxy = settings.preferredProxy {
            cfg.connectionProxyDictionary = proxy.connectionProxyDictionary
        }
        let session = URLSession(configuration: cfg, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw CheckError.http(-1)
        }
        guard http.statusCode == 302,
              let location = http.value(forHTTPHeaderField: "Location") else {
            // 200 = 无 release 或被网页端挑战（罕见）；其他状态按 HTTP 错误报
            throw CheckError.http(http.statusCode)
        }
        let tag = location.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/").last.map(String.init) ?? ""
        let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard !latest.isEmpty else { throw CheckError.badTag(tag) }
        return latest
    }

    /// 拒绝 HTTP 重定向的 session delegate（completionHandler(nil) = 不跟随）
    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private enum CheckError: Error {
        case http(Int)
        case badTag(String)
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case CheckError.http(200):
            return "GitHub 返回异常（未拿到重定向，可能被网页端挑战，请稍后再试）"
        case CheckError.http(let code):
            return "HTTP \(code)"
        case CheckError.badTag(let tag):
            return "Release tag 无效：\(tag)"
        default:
            return "网络错误：\(error.localizedDescription)"
        }
    }

    /// 升级入口：brew 安装则自动升级并重启，否则打开 Release 页
    @MainActor
    func performUpgrade() {
        if let brew = Self.brewPath(), Self.isInstalledViaBrew(brewPath: brew) {
            isUpgrading = true
            Self.runUpgradeScript(brewPath: brew, httpProxy: settings.httpProxy, socksProxy: settings.socksProxy)
            // 给 UI 一点时间展示「升级中」，随后脚本会接管（先等 app 退出）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSApplication.shared.terminate(nil)
            }
        } else {
            if let url = URL(string: "https://github.com/\(Self.owner)/\(Self.repo)/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - brew 探测与升级脚本

    /// 常见 brew 安装路径（Apple Silicon / Intel）
    static func brewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 是否通过 brew cask 安装（brew list --cask --versions 有输出即算）
    static func isInstalledViaBrew(brewPath: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: brewPath)
        p.arguments = ["list", "--cask", "--versions", "server-management"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            return p.terminationStatus == 0 && out.contains(caskName)
        } catch {
            return false
        }
    }

    /// 写升级脚本并 detached 执行：
    /// 等 app 退出 → brew upgrade → xattr 去隔离 → 重新启动
    /// 配置了代理时向脚本注入 HTTP(S)_PROXY 与 ALL_PROXY（brew 内部 curl 按需各取）
    static func runUpgradeScript(brewPath: String, httpProxy: ProxyConfig?, socksProxy: ProxyConfig?) {
        let brewDir = (brewPath as NSString).deletingLastPathComponent
        let appPath = "/Applications/\(appName).app"
        var proxyExports = ""
        if let http = httpProxy {
            let u = http.urlText
            proxyExports += """
            export HTTP_PROXY="\(u)" HTTPS_PROXY="\(u)"
            export http_proxy="\(u)" https_proxy="\(u)"

            """
        }
        if let socks = socksProxy {
            let u = socks.urlText
            proxyExports += """
            export ALL_PROXY="\(u)"
            export all_proxy="\(u)"

            """
        }
        let script = """
        export PATH="\(brewDir):/usr/bin:/bin:/usr/sbin:/sbin"
        \(proxyExports)
        for i in $(seq 1 15); do
            pgrep -x "\(appName)" >/dev/null 2>&1 || break
            sleep 1
        done
        sleep 1
        "\(brewPath)" upgrade --cask server-management >/tmp/\(caskName)-upgrade.log 2>&1
        if [ -d "\(appPath)" ]; then
            /usr/bin/xattr -cr "\(appPath)" 2>/dev/null
            /usr/bin/open -a "\(appPath)"
        fi
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(caskName)-upgrade-\(UUID().uuidString).sh")
        do {
            try script.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [url.path]
            // detached：app 退出后进程不随之终止
            p.qualityOfService = .utility
            try p.run()
        } catch {
            NSLog("升级脚本启动失败：\(error.localizedDescription)")
        }
    }
}
