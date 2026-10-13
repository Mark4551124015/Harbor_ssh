<p align="center">
  <img src="assets/brand/swift-app-icons/128.png" width="128" height="128" alt="Harbor 图标" />
</p>

<h1 align="center">Harbor</h1>

<p align="center">
  <strong>给那些你还在一行行敲的 SSH 操作，一个窗口。</strong>
</p>

<p align="center">
  服务器 · 跳板链 · 端口映射 · 密钥 · 进程活动<br />
  macOS 使用 Flutter · Windows 使用原生 WinUI 3（预览版）。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Built_with-Flutter-28796D?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/License-Apache--2.0-1f6feb?style=for-the-badge" alt="Apache License 2.0" />
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

---

<p align="center">
  <img src="assets/screenshots/workbench-dark.png" alt="Harbor 工作台，深色主题" width="1040" />
</p>

<p align="center">
  <img src="assets/screenshots/settings-light.png" alt="Harbor 设置，浅色主题" width="1040" />
</p>

## 一个窗口搞定

Harbor 直接打开你已经在用的 `~/.ssh/config`，给它一个真正的界面。浏览和搜索服务器、
分组、做端口映射、管理密钥，然后把手上的连接交给你习惯的终端——不用导入，也不用维护
第二份配置。

### 服务器

- 直接读写 `~/.ssh/config`；每次保存都在 `config_bk` 里存一份带时间戳的副本，文件夹超过 10 MB 时丢弃最旧的。
- 按别名、地址或分组搜索；收藏、最近连接、可折叠分组。
- 跳板链，以及每台服务器单独的用户、端口和身份文件。
- 常见项之外的 SSH 选项，从可搜索的列表里挑。
- 每台服务器一个图标，每个分组一个颜色和一个图标。
- 拖动排序、跨分组拖动，或选中多台一次性移动。
- 用 iTerm2、Terminal 或你系统默认的终端打开连接。

Harbor 只把自己能识别的连接写回 `~/.ssh/config`。原文件里的注释、`Include` / `Match`
结构和它不认识的指令不会出现在重写结果里；第一次保存还会重排文件——各 Host 块之间
插入一个空行，文件末尾也补一个空行。此前的版本都留在 `config_bk` 里。

### 端口映射

- 本地、远程和 SOCKS 映射各有自己的标签页，逐条启动、停止和删除。
- 一台服务器可以同时挂多条，不用开着终端也能一直跑。
- 连接超时与保活可调，也能针对单台服务器覆盖。

### 密钥

- 浏览 `~/.ssh`、查看指纹、一键复制公钥。
- 生成 Ed25519 或 RSA 4096 密钥，也可以导入已有的。

### 进程活动

- 列出 Mac 上所有 OpenSSH 进程，连同它们的连接、监听端口、PID 和运行时间。
- 一眼看出哪些是 Harbor 起的，哪些来自别处。
- 探测远端端点，看看连过去到底要多久。

### 按你的习惯来

- 明暗主题，跟随系统或固定。
- 五种强调色、减少动效、可搜索的设置。
- 选择 Harbor 启动时打开哪一页，以及边栏是否显示地址。

## 构建

Harbor 正在开发中。要从源码运行，需要 macOS、Flutter 3.38.9 SDK（见 `.fvmrc`）、
Xcode 及其命令行工具，以及 macOS 插件构建所需的 CocoaPods。

```sh
flutter pub get
flutter --no-version-check run -d macos
```

Release 构建：

```sh
flutter --no-version-check build macos --release
open build/macos/Build/Products/Release/Harbor.app
```

## Windows 原生预览版

Windows 应用位于独立的 `windows/` 目录，使用 C# / WinUI 3 实现，采用原生 Fluent
控件、系统强调色、明暗主题，以及受支持系统上的 Mica 背景。现有 macOS 应用与发布
流程保持独立。

工作区沿用 macOS 的页面结构：常驻的分组连接侧栏、Connection desk 工作台、收藏卡片、
活动摘要和支持分类搜索的设置页。启动时使用原生合成器实现模糊渐清；页面渐入
（190 毫秒）、分组与分段选择器动画（280 毫秒）、弹窗聚焦与缩放（320 毫秒）沿用
原版节奏。应用的减少动效选项和 Windows 动画设置均生效，支持 Harbor 原有的五种
强调色以及明暗配色。

预览版支持具名 SSH 服务器、搜索、收藏、分组、简单 Host 块的增删改、Windows Terminal
连接、本地/远程/SOCKS 转发、公钥指纹、公钥复制，以及在终端中交互生成 Ed25519 或
RSA 4096 密钥。活动页显示本窗口启动的转发进程；终端连接由终端管理。

配置文件为 `%USERPROFILE%\.ssh\config`。保存会保留注释、未知指令和其他 Host/Match
块，在 `config_bk` 中备份旧文件，并拒绝覆盖刷新后被其他程序修改过的文件。多个别名、
重复别名、多个 IdentityFile 或包含 Include 的 Host 块通过 **Open SSH config** 编辑。
列表只展示主配置文件中的具体别名；连接时由 OpenSSH 解析 Include、Match 和继承选项。
Windows 偏好与转发规则单独保存在 `%LOCALAPPDATA%\Harbor.Windows\settings.json`。

托管转发绑定回环地址，使用非交互的密钥或 ssh-agent 认证。请先在终端连接一次以确认
服务器信任并解锁密钥；关闭 Harbor 窗口会停止托管转发。如果服务器已经从配置继承了
转发指令，请通过终端连接运行它们，或先移除这些指令再启动单条托管转发。进程状态
不代表认证或目标服务已经就绪；转发页和活动页会显示 SSH 退出诊断。

标签、拖动排序、Include 文件内的别名发现、系统级进程活动、自动更新和签名的
Windows 安装包尚未实现。

在 Windows 10 2004 或更高版本上构建（推荐 Windows 11），需要 .NET 10 SDK 和
OpenSSH Client（`ssh.exe`、`ssh-keygen.exe`）。WinUI 原生依赖还需要对应架构的
[Microsoft Visual C++ Redistributable](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist)。
Windows SDK 构建工具由 NuGet 提供。在仓库根目录用 PowerShell 运行：

```powershell
.\windows\build.ps1 -Task Run
.\windows\build.ps1 -Task Test
.\windows\build.ps1 -Task Smoke  # 需要交互式 Windows 桌面，使用虚构数据。
.\windows\build.ps1 -Task Publish
```

自包含的 x64 预览版输出到 `windows/artifacts/win-x64/`；在此目录运行
`Harbor.Windows.exe`，分发时保留整个目录。`-Architecture ARM64` 可构建 ARM64 版，
目前尚未在 ARM 硬件上运行验证。脚本优先使用 `.local-only/dotnet/` 中的 SDK，否则
使用 PATH 中的 `dotnet`；也可以通过 `-Dotnet` 指定 SDK 可执行文件。SDK 不提交到仓库。
程序集版本与 macOS 发布一样，从 `pubspec.yaml` 读取。

## 版本命名

以 `pubspec.yaml` 为唯一版本来源，每次发布递增构建号。

| 字段 | Beta 示例 | 正式版示例 |
| --- | --- | --- |
| 应用/包版本 | `1.0.3-beta.1+5` | `1.0.3+7` |
| Git tag | `v1.0.3-beta.1` | `v1.0.3` |
| Release 标题 / changelog 标题 | `1.0.3-beta.1` | `1.0.3` |
| 安装包文件名前缀 | `Harbor-1.0.3-beta.1-` | `Harbor-1.0.3-` |

同一版本的连续测试版使用 `.1`、`.2` 等序号。Tag 固定加 `v` 前缀，不包含构建号。
macOS 的应用版本字段必须是纯数字，因此显示为 `1.0.3`，由构建号区分具体更新。
公开 Beta 继续作为普通 GitHub Release 发布并标记 Latest，供应用内更新发现。
Release changelog 统一使用英文。

修改版本号和 changelog 后，可生成并校验 tag：

```sh
python3 scripts/release.py tag
python3 scripts/release.py preflight --tag v1.0.3-beta.1
```

历史版本也统一为 `v<版本号>` tag；旧格式 tag 和重复 Release 入口已清理，
当前版本标记为 Latest。

## 许可证

Apache License 2.0 — 见 [LICENSE](LICENSE)。Copyright 2026 mark455。
