import Testing
@testable import ServerManagement

/// 版本比较与升级探测
struct UpdateCheckerTests {

    @Test("语义化版本比较：常规比较")
    func versionCompare() {
        #expect(UpdateChecker.isVersion("0.3.0", newerThan: "0.2.0"))
        #expect(UpdateChecker.isVersion("1.0.0", newerThan: "0.99.99"))
        #expect(UpdateChecker.isVersion("0.10.0", newerThan: "0.9.1"))
        #expect(!UpdateChecker.isVersion("0.2.0", newerThan: "0.3.0"))
        #expect(!UpdateChecker.isVersion("0.3.0", newerThan: "0.3.0"))
    }

    @Test("语义化版本比较：位宽不对齐补零")
    func versionCompareDifferentLength() {
        #expect(UpdateChecker.isVersion("0.3", newerThan: "0.2.9"))
        #expect(UpdateChecker.isVersion("0.3.1", newerThan: "0.3"))
        #expect(!UpdateChecker.isVersion("0.3", newerThan: "0.3.0"))
        #expect(!UpdateChecker.isVersion("1.0", newerThan: "1.0.1"))
    }

    @Test("当前版本读取：bundle 无版本信息时为 nil（开发模式）")
    func currentVersionInTests() {
        // 测试 runner 的 bundle 无 CFBundleShortVersionString（或为占位 1.0），应返回 nil
        #expect(UpdateChecker.currentVersion == nil)
    }

    @Test("brew 探测：不存在的路径返回 nil；cask 未安装返回 false")
    func brewDetection() {
        #expect(UpdateChecker.brewPath() == nil || UpdateChecker.brewPath()?.contains("brew") == true)
        // /usr/bin/true 退出码 0 但无输出，模拟「brew 在但未装该 cask」
        #expect(!UpdateChecker.isInstalledViaBrew(brewPath: "/usr/bin/true"))
        #expect(!UpdateChecker.isInstalledViaBrew(brewPath: "/usr/bin/false"))
    }
}
