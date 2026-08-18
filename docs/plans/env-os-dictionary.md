# 环境与操作系统字典管理 实现计划

> 关联 spec: ../specs/env-os-dictionary.md

### Task 1: 字典数据模型与 Store CRUD
- 改：新增 `Sources/ServerManagement/Models/Dictionaries.swift`（EnvDefinition/OSDefinition + hex↔Color 转换）、`Sources/ServerManagement/Store.swift`、`Tests/ServerManagementTests/StoreTests.swift`
- 内容：Snapshot 增 envs/oses 字段（缺省初始化内置默认）；env/os 增删改（重名校验）；改环境名同步刷写 Service.envs、改 OS 名同步刷写 Server.os；`color(for:)` 查询（nil 走默认规则）
- 验证：新增测试——默认初始化 / 增删改与重名拒绝 / 改名同步引用 / 删除后引用回退默认色 / round-trip 持久化
- [x] 完成

### Task 2: 管理界面
- 改：新增 `Sources/ServerManagement/Views/DictionarySettingsView.swift`、`Views/ServerListView.swift`（工具栏齿轮入口）
- 内容：偏好 sheet 双 tab；环境行：颜色井（NSColorWell）+ 名称（原地编辑）+ 删除确认；OS 行：名称原地编辑 + 删除确认；底部各自「添加」；重名输入红框提示
- 验证：`swift build`；运行后新增 gray 环境选紫色 → 服务胶囊变紫；改 OS 名 → 服务器下拉与存量数据同步
- [x] 完成

### Task 3: 调用点切换
- 改：`ServiceEditView` / `ServiceDetailView` / `ServerDetailView`（含 ServicePickerView）/ `ServerListView` / `ServerEditView` / `ServerImportView`
- 内容：commonEnvs/commonOSs 引用全部改 Store 字典；各 `envColor()` 删除，统一 `store.color(for:)`（详情页环境胶囊点击选择、表单胶囊、侧栏胶囊、选择器标签）
- 验证：`swift build`；手动过服务表单/详情/服务器表单/导入/侧栏五处颜色与候选一致
- [x] 完成

### Task 4: 回归与收尾
- 改：`docs/specs/server-management.md`（数据模型节补字典）、`Models/Service.swift` / `Models/Server.swift`（静态列表标注废弃）
- 验证：`./Scripts/test.sh` 全绿；`./Scripts/package-app.sh` 打包；手动过旧数据启动（缺省字典自动补默认）→ 改色 → 重启颜色保持
- [x] 完成
