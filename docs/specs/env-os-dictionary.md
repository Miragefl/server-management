# 环境与操作系统字典管理（env-os-dictionary）

## 目标
环境与操作系统由硬编码模板改为用户可管理的字典：支持新增/修改/删除，环境可配置颜色，全应用（表单快捷选项、胶囊配色）自动生效。

## 约束
- 技术栈不变：SwiftUI + JSON 存储，无第三方依赖
- 环境值仍以 String 存在于 Service.envs（不动现有数据模型），字典只管「候选 + 颜色」
- 删除字典项不影响已使用该值的服务（仅失去快捷选项与自定义颜色，回退灰色）
- 未配置颜色的环境回退现有默认色规则（prod 红 / uat 橙 / sit 蓝 / 其他灰）

## 模块拆解
- 数据模型：新增 `EnvDefinition`（name + colorHex）、`OSDefinition`（name）；Snapshot 增加 `envs: [EnvDefinition]` / `oses: [OSDefinition]` 字段，缺省时用内置默认值初始化（首启无感）
- Store：字典 CRUD（env 增删改 / os 增删改、重名校验、修改名时同步刷写引用它的 Service.envs 或 Server.os）；`color(for env:)` 查询
- 管理界面：设置入口（工具栏齿轮菜单）→ 偏好设置 sheet，两个 tab：环境列表（行内颜色井 + 名称 + 删除）、操作系统列表（名称 + 删除）；环境颜色用系统色板（NSColorWell）
- 替换调用点：`Service.commonEnvs` / `Server.commonOSs` 的所有 UI 引用改为 Store 字典；各视图 `envColor()` 改为 `store.color(for:)`（无配置走默认规则）

## 数据模型
- `EnvDefinition`：id、name（唯一，小写规范）、colorHex（如 "#FF5A5A"，nil 走默认规则）
- `OSDefinition`：id、name（唯一）
- 内置默认：sit 蓝 / uat 橙 / prod 红；OS 沿用现有 commonOSs 列表
- 设计遵循：字典与业务实体解耦，引用端只存字符串

## 关键决策
- 颜色存 hex 字符串而非枚举：JSON 友好、NSColorWell 双向转换简单
- 改环境名同步刷写引用：避免出现"旧名服务失去颜色/搜索不到"的僵尸数据；OS 同理
- 管理入口放工具栏齿轮而非独立窗口：保持单窗口心智，sheet 形式够用
- `Service.commonEnvs` / `Server.commonOSs` 保留但标记废弃（迁移期兼容），新代码一律走 Store

## 风险
- 大量服务引用时改名是 O(n) 全量刷写：个人工具量级（百级）无感知，接受
- 删除环境后服务仍显示该环境字符串：预期行为（数据不丢），spec 已注明回退灰色
- NSColorWell 在 CLT/SwiftUI 下的可用性：macOS 14 原生支持，风险低；降级方案为预设色板 Menu
