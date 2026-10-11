# Changelog

## 1.0.2-beta

### Added

- Update prompts now offer Skip this update, Ignore this version, and Update now, with ignored versions remembered across launches.
- Proxy settings support system, SOCKS, HTTP, and off modes, with separate controls for SSH connections and application updates.
- Server tags and tag search. Each server's Port Mapping page manages Local, Remote, and SOCKS forwarding rules that start with its SSH session.
- Global Port Mapping groups, tags, search, group start/stop, and context menus for creating, editing, moving mappings, and managing groups.
- Cmd-click multi-selection, Shift-click range selection, combined dragging, insertion indicators, group drop highlights, and edge auto-scrolling in global Port Mapping.
- Animated group expansion and collapse, sliding selection highlights, and combined drag previews, with stronger highlights for light and dark themes.
- A native macOS Identity file picker that opens `~/.ssh/` by default and shows hidden files.

### Changed and fixed

- Start all and Stop all operate on selected mappings when a selection exists. Clicking blank space, outside the page, or the search field clears the selection and restores the full scope.
- Removed standalone Start tunnel controls from server settings. Independent forwarding connections are started and stopped in global Port Mapping.
- Reordering and moving mappings between groups preserve mapping IDs, tags, and running connections. Collapsed groups expand after a drop, and mapping order is saved.
- Fixed Cmd+F failing after server fields receive focus. Search now targets connections or settings according to the current page.
- Fixed server header width changes and slight page shifts when buttons receive focus or tabs change.
- Improved error messages for failed update requests.

Published as a normal GitHub Release, with universal macOS ZIP and DMG packages, an update manifest, and SHA-256 checksums.

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
