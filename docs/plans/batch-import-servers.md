# 批量导入服务器 实现计划

> 关联 spec: ../specs/batch-import-servers.md

### Task 1: 区间表达式解析器
- 改：`Sources/ServerManagement/ServerRangeParser.swift`、`Tests/ServerManagementTests/ServerRangeParserTests.swift`
- 内容：`expand(_ text: String) -> (values: [String], failedSegments: [String])`；段格式 `前缀起始数~结束数` 或单值；英文/全角逗号/分号分隔；忽略空段；~ 后必须纯数字且 ≥ 起始数
- 验证：`./Scripts/test.sh` 新增套件全绿（`yd-vm121~125` 展开 5 个 / 单值段 / 多段混合 / 全角逗号 / 非法段进失败列表 / 结束<起始失败 / 空白容错）
- [x] 完成

### Task 2: Store 批量插入
- 改：`Sources/ServerManagement/Store.swift`、`Tests/ServerManagementTests/StoreTests.swift`
- 内容：`addServers(_:) -> (added: [Server], skipped: [Server])`，hostname 或 IP 与现存重复则跳过
- 验证：新增测试——批量插入 / 重复跳过 / 混合场景计数正确
- [x] 完成

### Task 3: 导入视图与入口
- 改：`Sources/ServerManagement/Views/ServerImportView.swift`、`Sources/ServerManagement/Views/ServerListView.swift`
- 内容：hostname/IP 表达式框（占位示例 `yd-vm121~125,yd-vm131~134`）+ 展开实时预览（前 8 条 + 总数，超 500 拒绝）+ OS 统一选择（Server.commonOSs 菜单）；hostname 与 IP 展开数不等或为 0 时禁用导入；结果弹摘要（成功 N / 跳过 M / 失败段明示）；工具栏 + 改菜单（单台新增… / 批量导入…）
- 验证：`swift build`；运行后输入示例表达式生成 9 台、重复行被跳过并提示
- [x] 完成

### Task 4: 回归与收尾
- 改：`docs/specs/server-management.md`（模块拆解节补批量导入）
- 验证：`./Scripts/test.sh` 全绿；`./Scripts/package-app.sh` 打包，手动过单台新增 / 批量导入 / 重复跳过三路径
- [x] 完成
