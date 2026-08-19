# ServerManagement

macOS 服务器信息记录工具：记录服务器（IP / 操作系统 / host）及其部署的服务（环境 / 端口 / 安装方式）。纯本地 JSON 存储，无第三方依赖。

## 安装

### Homebrew（推荐）

```bash
brew install --cask --no-quarantine Miragefl/tap/server-management
```

升级：

```bash
brew update
brew upgrade --cask --no-quarantine server-management
```

> **关于 `--no-quarantine`**：本应用未经 Apple 公证（需 $99/年开发者账号），带隔离属性安装会被 macOS 误报「已损坏」。`--no-quarantine` 跳过隔离标记即可正常使用。也可在 `~/.zshrc` 中一劳永逸：
>
> ```bash
> export HOMEBREW_CASK_OPTS="--no-quarantine"
> ```

### 手动安装

从 [Releases](https://github.com/Miragefl/server-management/releases) 下载 zip 解压，将 `ServerManagement.app` 拖入「应用程序」。若打开时提示「已损坏」，执行：

```bash
xattr -cr /Applications/ServerManagement.app
```

### 从源码构建

```bash
git clone https://github.com/Miragefl/server-management.git
cd server-management
./Scripts/package-app.sh   # 产物在 dist/ServerManagement.app
```

## 环境

- macOS 14+
- 仅需 Command Line Tools（无需完整 Xcode）

## 常用命令

```bash
swift build            # 构建
swift run              # 运行
./Scripts/test.sh      # 测试（自动兼容 CLT / Xcode 环境）
./Scripts/package-app.sh  # 打成可双击的 .app（dist/ServerManagement.app）
```

## 数据位置

`~/Library/Application Support/ServerManagement/data.json`（JSON 明文，可直接备份/编辑）

## 结构

```
Sources/ServerManagement/
├── App.swift              # 入口
├── ContentView.swift      # 左右分栏主界面
├── Store.swift            # 数据仓库：CRUD + JSON 持久化
├── Models/
│   ├── Server.swift       # 服务器实体
│   └── Service.swift      # 服务实体（serverID 外键）
└── Views/
    ├── ServerListView.swift    # 左栏：搜索 / 增删改
    ├── ServerEditView.swift    # 服务器表单
    ├── ServerDetailView.swift  # 右栏：详情 + 服务表格 + 环境筛选
    └── ServiceEditView.swift   # 服务表单
```
