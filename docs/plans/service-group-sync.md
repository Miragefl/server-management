# 服务组同步 实现计划

> 关联 spec: ../specs/service-group-sync.md

### Task 1: 数据模型扩展
- 改：`Sources/ServerManagement/Models/Service.swift`
- 内容：新增 `groupID: UUID?`，自定义解码 `decodeIfPresent` 默认 nil（旧 JSON 无感兼容），初始化器带默认值不破坏现有调用
- 验证：`swift build`；旧数据迁移测试仍绿
- [x] 完成

### Task 2: Store 组能力
- 改：`Sources/ServerManagement/Store.swift`、`Tests/ServerManagementTests/StoreTests.swift`
- 内容：`addService(_:to:)` 生成的记录共享同一 groupID；新增 `syncService(_ service:) -> Int`（把业务字段同步到同组其余记录，返回同步台数）与 `groupMembers(of:)` 查询
- 验证：新增测试——批量添加后三台共享组 / 同步只改业务字段不动 serverID 与 id / 单独 upsert 不影响同组
- [x] 完成

### Task 3: 编辑表单同步选择
- 改：`Sources/ServerManagement/Views/ServiceEditView.swift`
- 内容：编辑模式保存时，若服务有 groupID 且组内 >1 条，弹确认：仅本条（默认）/ 同步全组（N 台）；表单标题区展示所属组提示
- 验证：`swift build`；手动场景——编辑 yd-vm121 的 kafka 选同步后 122/123 一并更新
- [x] 完成

### Task 4: 详情页组角标
- 改：`Sources/ServerManagement/Views/ServerDetailView.swift`
- 内容：服务表格「服务名」列对组内服务显示「组 · N 台」小角标（help 提示批量同步入口在编辑）
- 验证：`swift build`；运行后组内服务可见角标
- [x] 完成

### Task 5: 回归与收尾
- 改：`docs/specs/server-management.md`（数据模型节补 groupID）
- 验证：`./Scripts/test.sh` 全绿；`./Scripts/package-app.sh` 打包并手动过一遍批量添加 → 组内编辑 → 同步/仅本条两条路径
- [x] 完成
