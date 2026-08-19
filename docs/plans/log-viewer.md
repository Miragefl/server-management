# 远程日志查看（log-viewer）实现计划

> 关联 spec: ../specs/log-viewer.md

### Task 1: 日志行模型 LogLine
- 新增：`Sources/ServerManagement/LogViewer/LogLine.swift`（ParsedLine 字段、LogLevel 枚举与 ParseLevel、Get(field) 取值）
- 新增：`Tests/ServerManagementTests/LogLineTests.swift`（级别识别大小写/别名、字段取值兜底）
- 验证：`./Scripts/test.sh`
- [ ] 完成

### Task 2: 解析器 LogParser
- 新增：`Sources/ServerManagement/LogViewer/LogParser.swift`（logback 正则 / JSON / plain 三规则按序；来源独立锁定；50 行未命中降级 plain）
- 新增：`Tests/ServerManagementTests/LogParserTests.swift`（三格式样例、来源锁定、降级路径、ANSI 色码剥离）
- 验证：`./Scripts/test.sh`
- [ ] 完成

### Task 3: 日志缓冲 LogBuffer
- 新增：`Sources/ServerManagement/LogViewer/LogBuffer.swift`（环形上限 5000、append 批量、级别过滤、关键词包含搜索/高亮词/隐藏词、匹配计数）
- 新增：`Tests/ServerManagementTests/LogBufferTests.swift`（上限淘汰、过滤组合、搜索命中）
- 验证：`./Scripts/test.sh`
- [ ] 完成

### Task 4: SSH 流式读取 SSHLogStreamer
- 新增：`Sources/ServerManagement/LogViewer/SSHLogStreamer.swift`（Process + /usr/bin/ssh 密钥认证；密码走 expect 包装、密码经环境变量；`tail -n N [-f] path`；stdout 按 \n 切行 AsyncStream 吐出；stderr/退出码转错误）
- 新增：`Tests/ServerManagementTests/SSHLogStreamerTests.swift`（用 `/bin/echo`、`/usr/bin/yes | head` 等本地命令冒烟流式切行；不测真 ssh）
- 验证：`./Scripts/test.sh`；手动 `swift run` 后对一台真实服务器冒烟
- [ ] 完成

### Task 5: 日志查看窗口 LogViewerWindow
- 新增：`Sources/ServerManagement/Views/LogViewerWindow.swift`（工具栏：follow/暂停、级别菜单、搜索框、高亮、隐藏、清屏；LazyVStack 列表 + 级别着色 + 贴底自动滚 + 合帧刷新）
- 改：`Sources/ServerManagement/App.swift`（注册 `WindowGroup(for: LogSession.self)`；LogSession 运行时注册表支持多开）
- 验证：`swift build`；手动开窗口连本地 `tail -f` 冒烟
- [ ] 完成

### Task 6: 入口集成
- 新增：`Sources/ServerManagement/Views/LogSessionConfigView.swift`（选凭据/手输 user@host、路径 + 最近 5 条（UserDefaults）、尾行数、follow 开关）
- 改：`Sources/ServerManagement/Views/ServerDetailView.swift`（工具栏「查看日志」按钮 → sheet → openWindow）
- 验证：`swift build`；手动从服务器详情打开日志窗口
- [ ] 完成

### Task 7: 回归与打包
- 验证：`./Scripts/test.sh` 全绿；`./Scripts/package-app.sh` 打包成功；手动过一遍主链路（列表 → 详情 → 查看日志 → follow → 搜索/过滤/暂停）
- [ ] 完成
