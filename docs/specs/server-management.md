# 服务器信息管理（server-management）

## 目标
做一个 macOS 原生应用，集中记录服务器基础信息及其部署的服务明细（环境/端口/安装方式），替代散落的表格与笔记。

## 约束
- 技术栈：Swift 5.10+ / SwiftUI / SwiftData / SPM，无第三方依赖，macOS 14+
- 纯本地存储，单机使用；不做登录、不做网络同步
- 只做信息记录（CRUD + 搜索过滤），不做远程连接/监控等运维动作

## 模块拆解
- 数据模型：`Server`（服务器）与 `Service`（服务）独立实体，`Deployment` 多对多关联
- 服务器管理：列表（搜索/排序）、新增、编辑、删除、批量导入（区间表达式 `yd-vm121~125` 自动递增展开，OS 统一设定）
- 服务管理：独立服务库（侧栏第二区块）CRUD；一处编辑全局生效；通过绑定/解绑与服务器关联
- 绑定关系：服务器详情「绑定服务」多选弹窗；服务表单「部署到服务器」多选；解绑保留双方记录
- 入口与导航：左侧双区块列表 + 右侧详情，macOS NavigationSplitView 布局

## 数据模型
- `Server`：id、hostname、ips（多 IP）、os、group（分组名，空 = 未分组）、cpu、memory、disk、credentials（账号列表）、remark、createdAt、updatedAt
- `Service`：id、name、envs（环境数组）、ports（端口数组，每项带可选描述）、installMethod、group（分组名，空 = 未分组）、credentials（账号列表）、remark
- `Credential`：id、username、password、remark（用途，如 root / 管理后台）、createdAt（内嵌于宿主实体，随宿主级联删除；全空行保存时过滤）
- `Deployment`：id、serverID、serviceID、createdAt（多对多连接记录，重复绑定幂等忽略）
- 字典：`EnvDefinition`（name + colorHex?）、`OSDefinition`（name）、`GroupDefinition`（name，服务器与服务共用一套），存于 data.json（key：envDictionary / osDictionary / groupDictionary），缺省自动初始化内置默认；改环境/OS/分组名会同步刷写业务数据引用；颜色自定义优先、未配置回退默认规则（prod 红 / uat 橙 / sit 蓝 / 其他灰）
- 分组：侧栏两大区块内按分组嵌套小标题（字典序 + 未分组垫底）；新增/批量导入/详情页可就地选择分组；搜索载体含分组名
- 删除语义：删服务器→级联删其 Deployment（服务保留）；删服务→级联删其 Deployment（服务器保留）；删环境/OS 字典项→业务数据旧值保留；删分组字典项→成员归属清空（变为未分组）
- 存储为 JSON 文件（App Support 目录），连接 key 磁盘名为 `bindings`

## 关键决策
- 服务与服务器独立 + `Deployment` 连接记录而非彼此内嵌：双向查询对称、去重容易、一处编辑全局生效
- JSON 文件不选 SwiftData：本机仅有 CLT，SwiftData 宏插件 Xcode 独占无法编译；个人工具量级（百级记录）JSON 足够
- 选 SPM 不选 .xcodeproj：命令行可构建可测试，Xcode 打开 Package.swift 即可开发；后续需要 .app 分发再补打包脚本
- 选 NavigationSplitView 不选多窗口：工具型单窗口应用交互最简
- Store 用 @MainActor ObservableObject：UI 直连，读写集中一处便于测试

## 风险
- JSON 并发写损坏：单窗口单 Store 串行写，风险可忽略；写入失败时弹提示
- env/port 后续可能有"一个服务多环境/多端口"诉求：首版保持单值 + remark 兜底，需要时再加子表
- 数据量增长后搜索变慢：千级以下无感知，超过再迁 SQLite
