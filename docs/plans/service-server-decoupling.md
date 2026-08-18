# 服务独立与绑定关系重构 实现计划

> 关联 spec: ../specs/service-server-decoupling.md

### Task 1: 数据模型重构（含迁移）
- 改：`Sources/ServerManagement/Models/Service.swift`（去 serverID/groupID，兼容解码）、新增 `Models/Binding.swift`
- 内容：Service 独立实体化；解码旧 JSON：按 serverID 生成绑定、同 groupID 合并为单服务（保留首条业务字段）；Binding 唯一约束 serverID+serviceID
- 验证：`swift build`；新增迁移测试（旧格式含 groupID 三条 → 一服务三绑定；无 groupID 各自独立）
- [x] 完成

### Task 2: Store 重写绑定层
- 改：`Sources/ServerManagement/Store.swift`、`Tests/ServerManagementTests/StoreTests.swift`
- 内容：Snapshot 增加 bindings；`bind/unbind`、双向查询、幂等绑定；`deleteServer` 级联删绑定；`deleteService` 级联删绑定；移除 `addService(_:to:)`/`syncService`/`groupMembers`；搜索经绑定关联（载体 = 服务字段本身）
- 验证：重写测试套件——绑定/解绑/幂等/双向级联/搜索语义/round-trip 全绿
- [x] 完成

### Task 3: 侧栏双区块 + 服务器详情改造
- 改：`Sources/ServerManagement/ContentView.swift`、`Views/ServerListView.swift`、`Views/ServerDetailView.swift`
- 内容：侧栏分「服务器」「服务」两个 Section（各自计数）；服务器详情表格数据源改为经绑定取服务 + 「绑定服务…」按钮（弹多选已有服务列表，支持搜索）；解绑入口（原删除按钮改为解绑，确认弹窗）
- 验证：`swift build`；手动——绑定两个服务到服务器、解绑后服务仍在服务列表
- [x] 完成

### Task 4: 服务独立管理页 + 表单简化
- 改：新增 `Views/ServiceListView.swift`、改 `Views/ServiceEditView.swift`
- 内容：服务列表（名称/环境/端口/安装方式/绑定数 + 增删改）；服务表单去掉服务器多选区与同步弹窗，新增「部署到服务器」多选区（绑定集合，新增=创建+绑定，编辑=调整绑定）；删除服务确认弹窗提示将解除 N 台绑定
- 验证：`swift build`；手动——新建服务并勾选 3 台、编辑改字段后服务器详情同步可见
- [x] 完成

### Task 5: 回归与收尾
- 改：`docs/specs/server-management.md`（数据模型/模块拆解同步新架构）、`README.md` 结构图
- 验证：`./Scripts/test.sh` 全绿；`./Scripts/package-app.sh` 打包，手动过完整路径：旧数据启动迁移 → 绑定/解绑 → 搜索 → 删除级联
- [x] 完成
