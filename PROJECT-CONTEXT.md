# PROJECT-CONTEXT

## 项目定位
macOS 原生桌面应用：记录服务器信息（IP / OS / host）及其部署的服务（环境 / 端口 / 安装方式）。个人工具，纯本地存储。

## 技术栈
- 语言：Swift 5.10+（Xcode 工具链，macOS 14+ SDK）
- UI：SwiftUI（@main App 生命周期）
- 存储：JSON 文件（`~/Library/Application Support/ServerManagement/data.json`，Codable + 自管 Store）
  - 原因：本机仅有 CLT 无完整 Xcode，SwiftData 宏插件 Xcode 独占无法编译；个人工具量级 JSON 足够
- 构建：Swift Package Manager（`swift build` / `swift run` / `swift test`；Xcode 可直接打开 Package.swift 开发）
- 最低系统：macOS 14 Sonoma（SwiftData 要求）

## 常用命令
- 构建：`swift build`
- 运行：`swift run`
- 测试：`./Scripts/test.sh`（不能直接 `swift test`：CLT 下 Testing.framework 与宏插件不在默认搜索路径，脚本会自动注入 `-F` / `-load-plugin-library` / rpath）
- 打包 .app：`./Scripts/package-app.sh`（产物在 `dist/ServerManagement.app`）

## 目录结构（规划）
```
Sources/ServerManagement/   # 应用代码（App 入口 / Views / Models）
Tests/ServerManagementTests/ # 模型与逻辑单测
docs/specs/                  # 需求 spec
docs/plans/                  # 实现 plan
```

## 约定
- 无外部第三方依赖（SwiftUI + Foundation 足够）
- 中文注释与文档；代码标识符英文
- 不用 Xcode 独占宏插件可用性之外的 API；`#Preview` 宏在本机 CLT 下无法编译，禁用
- 数据模型改动需同步更新 docs/specs 中的数据模型节
