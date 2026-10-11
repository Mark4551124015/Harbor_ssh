# Changelog

## 1.0.2-beta

### 新增

- 更新弹窗支持“跳过本次更新”“忽略此版本”和“立即更新”，并记住忽略的版本。
- 代理设置支持系统代理、SOCKS、HTTP 和关闭；SSH 连接与应用更新可分别选择是否走代理。
- 服务器支持标签管理与标签搜索；服务器内的 Port Mapping 页面管理随 SSH 会话启动的 Local、Remote 和 SOCKS 转发规则。
- 全局 Port Mapping 支持分组、标签、搜索、分组启动与停止，以及右键新建、编辑、移动到组和组管理。
- 全局 Port Mapping 支持 Cmd 多选、Shift 连选、合并拖动、插入横线、拖入组高亮和边缘自动滚动。
- 分组展开收起、选中滑块和合并拖动加入动画；选中和拖入组高亮适配浅色、深色主题。
- Identity file 使用 macOS 原生文件选择器，默认打开 `~/.ssh/` 并显示隐藏文件。

### 调整与修复

- Start all / Stop all 在有选中项时只操作所选；点击空白、页面外或搜索框取消选择后，恢复操作全部。
- 服务器页面移除独立 Start tunnel 操作；独立转发连接统一在全局 Port Mapping 中启动和停止。
- 拖动排序和跨组移动保留映射 ID、标签及运行中的连接；收起的组接收映射后自动展开，排序保存后保留。
- 修复服务器页面获得焦点后 Cmd+F 失效的问题，并按当前页面打开连接或设置搜索。
- 修复服务器顶栏按钮获得焦点、分页标签切换时宽度变化和页面轻微平移的问题。
- 改善更新请求失败时的错误提示。

发布为普通 GitHub Release，包含 macOS universal ZIP、DMG、更新清单及 SHA-256 校验文件。

## beta-1.0.1

- Automatic update checks at startup, manual checks in Settings, and in-app installation with checksum verification and restart.
- Closing a window preserves controllable port mappings; quitting stops all owned mappings, including starts in flight.
- Startup uses a fixed-size logo over the blurred interface, with a 500 ms hold and 500 ms fade.
- Published as a normal GitHub Release.

## 1.0.0-beta.1

First public build. Distributed without a Developer ID, so macOS asks the user to
allow it in System Settings on first launch.

- SSH connection library backed by `~/.ssh/config`, with groups, favorites, custom icons and batch drag organization.
- External terminal connections, ProxyJump, independent Local / Remote / SOCKS mappings and SSH key management.
- Every option in the Advanced picker survives a save, a restart and a second save.
- Config read and write failures surface in the window, and Save & Connect stops when the write fails.
- Each save files a timestamped copy of the replaced config in `config_bk`, kept under 10 MB.
- A host library written under the old `com.example` bundle identifier is adopted once, without overwriting newer data.
- Searchable settings, theme and accent preferences, reduced motion and stable category transitions.
- Live system OpenSSH activity and TCP connection probes.
- GitHub Actions quality checks, unsigned universal macOS packages, and a publish job that uploads every asset before clearing the draft.
