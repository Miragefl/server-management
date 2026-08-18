# 服务器信息管理 实现计划

> 关联 spec: ../specs/server-management.md

### Task 1: 项目骨架
- 改：`Package.swift`、`Sources/ServerManagement/{App.swift, ContentView.swift}`
- 内容：SPM 可执行目标，@main App + 空 NavigationSplitView 窗口
- 验证：`swift build` 通过；`swift run` 弹出空窗口
- [x] 完成

### Task 2: 数据模型与 Store
- 改：`Sources/ServerManagement/Models/{Server.swift, Service.swift}`、`Sources/ServerManagement/Store.swift`、`App.swift`（注入 Store）
- 内容：Server / Service 两个 Codable struct（serverID 外键）；Store 负责内存 CRUD + JSON 持久化（App Support），Server 删除级联删 Service；port 校验 1-65535
- 验证：`swift build` 通过；`Tests/ServerManagementTests/StoreTests.swift`（级联删除 / 增改删 / 持久化 round-trip）通过（`swift test`）
- [x] 完成

### Task 3: 服务器列表与管理
- 改：`Sources/ServerManagement/Views/ServerListView.swift`、`Views/ServerEditView.swift`、`ContentView.swift`
- 内容：左栏列表（搜索框按 hostname/ip/os 过滤）、新增/编辑表单、删除确认
- 验证：`swift build`；运行后可新增一条服务器并搜索命中
- [x] 完成

### Task 4: 服务器详情与服务管理
- 改：`Sources/ServerManagement/Views/{ServerDetailView.swift, ServiceEditView.swift}`
- 内容：右栏展示服务器基本信息 + 服务表格（列：名称/环境/端口/安装方式）；服务增删改；顶部环境筛选（全部/sit/uat/prod）
- 验证：`swift build`；运行后为服务器添加服务、按环境筛选、删除服务后列表正确刷新
- [x] 完成

### Task 5: 打磨与打包（可选）
- 改：`Scripts/package-app.sh`、`README.md`
- 内容：空态提示、复制 IP 快捷操作；脚本把 swift build 产物打成最小 .app bundle
- 验证：`swift build && ./Scripts/package-app.sh` 生成可双击运行的 .app
- [x] 完成

### Task 6: 回归与收尾
- 改：全部
- 验证：`swift build && swift test` 全绿；手动过一遍 spec 中所有 CRUD 场景；同步更新 spec 数据模型节（如有偏差）
- [x] 完成
