<p align="center">
  <img src="assets/brand/swift-app-icons/128.png" width="128" height="128" alt="Harbor 图标" />
</p>

<h1 align="center">Harbor</h1>

<p align="center">
  <strong>给那些你还在一行行敲的 SSH 操作，一个窗口。</strong>
</p>

<p align="center">
  服务器 · 跳板链 · 端口映射 · 密钥 · 进程活动<br />
  使用 Flutter 为 macOS 构建。
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
