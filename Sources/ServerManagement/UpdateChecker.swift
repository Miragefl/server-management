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
    @MainActor
    func checkForUpdates() async {
        guard let current = Self.currentVersion else {
            state = .failed("开发模式（无版本信息），请从 Release 安装后使用自动升级")
            return
        }
        state = .checking
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await makeSession().data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                state = .failed("GitHub 接口不可用（HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)）")
                return
            }
            struct Release: Decodable { let tag_name: String }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            guard !latest.isEmpty else {
                state = .failed("Release tag 无效：\(release.tag_name)")
                return
            }
            state = Self.isVersion(latest, newerThan: current)
                ? .available(version: latest)
                : .upToDate
        } catch {
            state = .failed("网络错误：\(error.localizedDescription)")
        }
    }

    /// 升级入口：brew 安装则自动升级并重启，否则打开 Release 页
    @MainActor
    func performUpgrade() {
        if let brew = Self.brewPath(), Self.isInstalledViaBrew(brewPath: brew) {
            isUpgrading = true
            Self.runUpgradeScript(brewPath: brew, proxy: settings.proxy)
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

    /// 检查更新用的会话：配置了代理走代理，否则系统默认（直连）
    private func makeSession() -> URLSession {
        guard let proxy = settings.proxy else { return .shared }
        let cfg = URLSessionConfiguration.default
        cfg.connectionProxyDictionary = proxy.connectionProxyDictionary
        return URLSession(configuration: cfg)
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
    /// 配置了代理时向脚本注入 HTTP(S)_PROXY / ALL_PROXY（brew 内部 curl 走代理）
    static func runUpgradeScript(brewPath: String, proxy: ProxyConfig?) {
        let brewDir = (brewPath as NSString).deletingLastPathComponent
        let appPath = "/Applications/\(appName).app"
        var proxyExports = ""
        if let proxy {
            let u = proxy.urlText
            proxyExports = """
            export HTTP_PROXY="\(u)" HTTPS_PROXY="\(u)" ALL_PROXY="\(u)"
            export http_proxy="\(u)" https_proxy="\(u)" all_proxy="\(u)"
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
