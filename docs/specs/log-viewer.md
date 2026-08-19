# 远程日志查看（log-viewer）

## 目标
参考 LogView（../log，Go TUI 日志查看器），在 server-management 中内置日志查看功能：从服务器详情一键 SSH 到目标机 tail 日志，在独立窗口实时查看、过滤、搜索。

## 约束
- 技术栈不变：SwiftUI + Foundation，零第三方依赖（不引 Swift SSH 库）
- SSH 走子进程 `/usr/bin/ssh`（复用 Server.credentials 里的账号）
- 不做（后续增强，见下）：k8s 数据源、高级搜索语法（field:value/AND/OR/NOT）、书签/统计面板/导出、YAML 规则配置、多文件聚合

## 模块拆解
- `LogViewer/LogLine`：结构化日志行（time/level/thread/traceId/logger/message/source + raw），LogLevel 枚举
- `LogViewer/LogParser`：解析器，内置三规则按序匹配（java-logback 正则 / JSON / plain 兜底），每个来源独立锁定，50 行未命中降级 plain（对齐 LogView 行为）
- `LogViewer/LogBuffer`：环形缓冲（上限 5000 行），级别过滤、关键词搜索/高亮/隐藏
- `LogViewer/SSHLogStreamer`：Process 包装 `ssh user@host "tail -n N [-f] /path"`，AsyncStream 逐行输出；密码认证用 `/usr/bin/expect` 包装（密码经环境变量传入，不进 ps 参数）
- `Views/LogViewerWindow`：独立窗口（新 WindowGroup，可多开）。工具栏：follow/暂停、尾行数、级别快捷过滤（全部/仅ERROR/+WARN/去DEBUG）、搜索框、高亮关键词、隐藏关键词；日志列表 LazyVStack + 级别着色 + 贴底自动滚动
- `Views/LogSessionConfigView`：入口配置 sheet——选服务器凭据（或手输 user@host）、日志路径（记忆最近 5 条，UserDefaults）、尾行数、是否 follow
- 入口：ServerDetailView 工具栏「查看日志」按钮

## 数据模型
- 无 schema 变更：不新建持久化实体；LogSession 为运行时对象，最近路径存 UserDefaults

## 关键决策
- 独立窗口而非 sheet：日志需要大视窗、可多开对照，sheet 模态体验差
- 子进程 ssh 而非 SSH 库：守住零依赖约定；密码认证靠 macOS 自带 expect 包装，密钥认证直接透传
- GUI 原生渲染（SwiftUI 列表）而非内嵌终端：可做级别着色/结构化列，与 app 风格统一
- 环形缓冲 5000 行固定上限 + 批量合帧刷新：防 SwiftUI 大数据卡死（对齐 LogView history=5000）
- MVP 搜索为「包含匹配 + 级别过滤」：高级语法留待增强，先跑通主链路

## 风险
- 大量日志行渲染卡顿：环形上限 + ~100ms 合帧 + LazyVStack；仍卡再降级为 TextCanvas
- 密码认证兼容性（expect 交互异常）：错误流透传到 UI 提示；密钥认证为主推路径
- follow 时翻看历史被强制拉底：stick-to-bottom——仅当用户已贴底才自动滚
