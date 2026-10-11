<p align="center">
  <img src="assets/brand/swift-app-icons/128.png" width="104" alt="Harbor logo" />
</p>
<h1 align="center">Harbor SSH</h1>
<p align="center">服务器、密钥与端口映射，一处管理。</p>
<p align="center">
  <img alt="Platform macOS" src="https://img.shields.io/badge/platform-macOS-30363D" />
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built_with-Flutter-28796D" />
  <img alt="OpenSSH" src="https://img.shields.io/badge/connects_with-OpenSSH-9A5427" />
</p>
<p align="center">
  <a href="#功能">功能</a> · <a href="#开始使用">开始使用</a> · <a href="#操作方式">操作方式</a> · <a href="#数据与配置">数据与配置</a>
</p>

Harbor 是面向 macOS 的本地 SSH 管理器。用分组与收藏整理服务器，用独立页面维护密钥和隧道，连接交给你习惯的外部终端。

本项目借助 **OpenAI Codex** 开发，Codex 参与界面实现、功能开发、测试与文档编写。

目前处于开发阶段；可从源码运行和构建。

## 界面预览

工作台 · 深色主题

![Harbor 工作台](assets/screenshots/workbench-dark.png)

设置 · 浅色主题

![Harbor 设置](assets/screenshots/settings-light.png)

截图使用虚构服务器数据；文档渲染使用替代字体，运行时使用 macOS 系统字体。

## 功能

| 工作流 | 支持内容 |
| --- | --- |
| 服务器库 | 读取 `~/.ssh/config`；新建、重命名、删除连接；收藏、最近连接、分组与搜索 |
| 连接 | 系统默认终端、iTerm2 或 Terminal；SSH 密钥、端口、用户及 ProxyJump 跳板链 |
| 整理 | 自选连接图标、分组颜色与图标；调整边栏宽度；拖动排序与跨组移动；多选批量移动 |
| 端口映射 | 独立的 Local / Remote / SOCKS 管理页；同一服务器可建立多个条目，逐条启动、停止和删除 |
| 活动监视 | 自动发现本机 OpenSSH 进程；显示外部终端与 Harbor 的 TCP 连接、监听端口、PID 和运行时间；手动测试端口连接耗时 |
| 密钥 | 浏览本机 SSH 密钥、查看指纹、复制公钥、导入私钥、生成 Ed25519 / RSA 4096 密钥 |
| 个性化 | 跟随系统或固定明暗主题；五种强调色；减少动效；列表地址显示；默认启动页 |
| 高级选项 | 按需添加 SSH 选项；搜索名称与说明；编辑、移除已配置项，保留已有自定义选项 |
| 连接偏好 | 外部终端选择、隧道连接超时与 SSH 保活间隔；服务器自定义选项优先 |
| 设置 | 搜索设置项；管理最近记录；在 Finder 中定位配置；复制基础诊断信息；重置偏好 |

高级选项的说明参考 [OpenSSH ssh_config 文档](https://man.openbsd.org/ssh_config)。新增空白条目不会写入配置；填写值后沿用连接的保存流程。

### 三种映射，三个用途

| 类型 | 监听位置 | 典型用途 |
| --- | --- | --- |
| Local `-L` | 本机 | 通过服务器访问内网数据库或服务 |
| Remote `-R` | 远端服务器 | 让远端访问本机开发服务；公网监听还取决于服务器 SSH 配置 |
| SOCKS `-D` | 本机 | 为支持 SOCKS 的应用提供经由 SSH 的代理 |

全局映射由 Harbor 单独运行 SSH 进程管理，保存在应用数据中，不写入 SSH config，也不继承 config 中已有的转发规则。保存条目不等于自动启动。

### 本机 SSH 活动

Workbench 显示最多四条进程，Activity 页提供完整列表及连接、监听筛选，每五秒刷新。点击条目查看详情；外部进程仅观察，不会被 Harbor 接管或停止。进程数不等于逻辑会话数，监听端口也不等于转发规则数。TCP 端点的可见范围受当前用户权限限制；内嵌 SSH 库且未启动 `ssh` 进程的客户端不在监视范围内。

网络诊断由用户手动触发，向详情中第一个观察到的远端 TCP 端点建立三次连接，显示各次及平均连接耗时。该结果不代表 SSH 会话延迟或上下行带宽，也不测量跳板后的完整路径。

## 开始使用

需要 macOS、Flutter 3.38.9 SDK（见 `.fvmrc`）、Xcode 及其命令行工具；macOS 插件构建需要 CocoaPods。先通过 `flutter doctor` 检查本机构建环境。

在项目根目录运行：

```sh
flutter pub get
flutter --no-version-check run -d macos
```

如果 Flutter 尚未加入 PATH，使用 SDK 的完整路径，例如：

```sh
/Users/你的用户名/SDKs/flutter/bin/flutter --no-version-check run -d macos
```

构建可直接运行的 macOS 应用：

```sh
flutter --no-version-check build macos --release
open build/macos/Build/Products/Release/Harbor.app
```

构建产物为 `Harbor.app`。GitHub Actions 支持生成测试包，以及可选的 Developer ID 签名与 Apple 公证。

## 操作方式

- 在列表空白处或分组上右键，新建分组或连接；连接与分组的右键菜单提供重命名、外观和整理操作。
- 按住 `Shift` 连选，`⌘` / `Ctrl` 切换选中，再拖动一次性移动。连接之间的横线表示插入位置，分组卡片高亮表示移入该组；靠近列表上下边缘时自动滚动。
- 收藏条目与分组标题都支持拖动排序。拖动边栏边缘调整宽度，双击边缘恢复默认宽度。
- 左下角齿轮打开设置，右侧显示应用版本。外观立即生效，启动页在下一次启动时使用，隧道偏好应用于新启动的隧道。
- 选择系统默认终端时，Harbor 通过 `.command` 文件的默认打开应用启动连接。iTerm2 可通过其“Make iTerm2 Default Term”设置接管，也可在 Harbor 设置中直接选择 iTerm2。

| 快捷键 | 操作 |
| --- | --- |
| `⌘K` | 打开 / 关闭 Quick Connect；方向键选择，Return 连接 |
| `⌘F` / `Ctrl F` | 设置页搜索设置，其他页面显示并聚焦边栏搜索 |
| `⌘N` | 新建连接 |
| `⌘S` | 保存 SSH 配置 |
| `⌘,` | 打开设置 |
| `F2` | 重命名选中的连接 |
| `Escape` | 关闭弹层、收起搜索或返回上一页 / 主界面 |

## 数据与配置

| 数据 | 存放位置与行为 |
| --- | --- |
| SSH 连接参数 | `~/.ssh/config`；保存时生成 `.bak` 备份 |
| 分组、收藏、排序、图标、最近记录 | 应用支持目录中的 `host-library.json` |
| 全局映射和设置偏好 | 同一个 `host-library.json`，与 SSH config 独立 |
| 密钥 | 本机 `~/.ssh`；导入与生成时使用受限文件权限 |

设置中的 **Data & privacy** 可以在 Finder 中定位数据文件、关闭最近连接记录或清空已有记录。基础诊断只包含系统版本和数量信息，不包含服务器地址或密钥内容。

**当前配置保存的边界：** 保存连接会重写程序支持的字段，不能完整保留原文件的注释、`Include` / `Match` 结构或全部自定义语法。复杂 SSH 配置请保留单独备份。

## CI / Release

PR 和 main 推送执行格式检查、静态分析、回归测试、覆盖率收集与 macOS Release 构建。版本 tag 或手动运行可生成 GitHub Release 草稿，包含 Universal ZIP、DMG、SHA256 和构建清单；支持可选 Developer ID 签名与公证。

当前处于开发阶段，尚未公开发布。签名流程使用 GitHub Actions secrets；未签名构建标记为测试预发布。

## 开发

```sh
flutter --no-version-check test
flutter --no-version-check build macos --debug
```

- [主程序与 SSH 状态](lib/main.dart)
- [主题与界面组件](lib/harbor_ui.dart)
- [设置与偏好](lib/settings.dart)
- [密钥管理](lib/key_management.dart)
- [交互和 SSH 回归测试](test/)
- 文档截图：`flutter test tool/readme_previews.dart`（macOS，虚构数据，不读取用户配置）

应用内标记来自 `assets/brand/harbor-mark.png`，Dock 图标源为 `assets/Harbor Terminal Icon.png`。重新生成 macOS 图标：

```sh
python3 scripts/generate_app_icon.py
```

脚本依赖 Pillow、NumPy 和 SciPy。经典 `AppIcon.appiconset` 使用单一 Dock 图标；界面明暗主题与应用图标是独立设置。

## 设计参考

README 的信息顺序与可搜索设置的方向参考了 [pebrel](https://github.com/Kuddev/pebrel)。

Harbor 为当前工作名称。
