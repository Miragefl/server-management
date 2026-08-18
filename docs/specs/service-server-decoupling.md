# 服务独立与绑定关系重构（service-server-decoupling）

## 目标
把「服务从属于服务器」重构为「服务与服务器独立 + 多对多绑定」，一处编辑全局生效，支持随时绑定/解绑。

## 约束
- 技术栈不变：SwiftUI + JSON 存储，无第三方依赖
- 现有数据自动迁移：旧 `Service.serverID` 数据读取时转为「独立服务 + 绑定」，无感升级
- 保留现有交互习惯：搜索、环境筛选、批量导入服务器等能力不变

## 模块拆解
- 数据模型：
  - `Service` 去掉 `serverID` 与 `groupID`，成为独立实体（name/envs/port/installMethod/remark）
  - 新增 `Binding`：`id + serverID + serviceID + createdAt`，多对多连接记录
- Store：
  - 绑定管理：`bind(serviceIDs:to:)` / `unbind(_:)` / `bindings(of server/service)` 查询
  - 服务 CRUD 改为纯实体操作（删除服务时级联删其绑定，解绑不删服务；删服务器级联删其绑定）
  - 旧 `groupID` 组在迁移时**合并为单服务 + N 绑定**（组语义被绑定自然取代）
  - 服务器搜索的「载体」逻辑改为经绑定关联
- UI：
  - 侧栏改为两个 Section：服务器 / 服务（各自列表 + 搜索共用）
  - 服务器详情：绑定服务表格 + 「绑定服务」按钮（多选已有服务）
  - 服务列表页：独立 CRUD + 每行显示已绑定服务器数；详情/编辑里管理绑定（勾选服务器）
  - 编辑服务不再需要「同步全组」弹窗（改一处即全局生效），相关代码删除

## 数据模型
- `Service`：id、name、envs、port?、installMethod、remark、createdAt、updatedAt
- `Binding`：id、serverID、serviceID、createdAt（唯一约束 serverID+serviceID，重复绑定幂等忽略）
- 兼容性：解码旧 JSON 时按 serverID 生成绑定；同 groupID 的旧服务合并为一条（保留首条的 id 与业务字段）
- 设计遵循：连接记录独立建模而非彼此存数组，便于双向查询与去重

## 关键决策
- 多对多连接表 `Binding` 而非 Server 内嵌 serviceIDs：双向查询对称、去重容易、JSON 持久化简单
- 删除语义：删服务器→级联删绑定（服务保留）；删服务→级联删绑定（服务器保留）；解绑→只删绑定
- 旧 groupID 组迁移合并：组的本意（一处改处处生效）由绑定天然实现，合并避免出现三条重复服务
- 服务列表进侧栏 Section 而非单独窗口/Tab：与服务器同级心智，导航一致

## 风险
- 迁移合并丢失单台差异（组内曾被「仅本条」改过的记录）：以组内**首条**为准，可接受（用户上次确认过清数据的宽松态度，且差异可在迁移后重新编辑）
- UI 改动面较大：侧栏/详情/表单三处，按 Task 拆分逐步替换，每步可编译
- 搜索「kafka sit」语义：载体改为「服务自身字段 + 经绑定归属」，保持现行为
