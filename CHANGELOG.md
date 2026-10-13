# Changelog

## 1.0.6

### Added

- Add a native Windows application preview with SSH host management, grouped connections, and Local, Remote, and SOCKS port forwarding.
- Publish Windows x64 and ARM64 packages in both self-contained and framework-dependent .NET 10 variants.
- Keep sidebar group titles pinned while scrolling until the next group replaces them.

### Build and distribution

- Publish a stable release with build number 8 and Windows packages alongside the universal macOS ZIP and DMG.
- Include all macOS and Windows release archives in the shared SHA-256 checksum file.

## 1.0.5

### Fixed

- Build CI and release packages with Xcode 26 so native window controls use the current macOS appearance, matching local builds instead of the older SDK compatibility style.
- Fix the Dependabot lint upgrade by resolving the lockfile with the project's pinned Flutter SDK, preserving SDK-pinned dependency versions.
- Update flutter_lints to 6.0.0 and fix unused callback parameter declarations for a clean static analysis run.

### Build and distribution

- Publish a stable release with no beta suffix, refreshed universal macOS ZIP and DMG packages, and build number 7 for in-app updates.
- Include the Xcode and macOS SDK versions in the release manifest to make build differences traceable.
- Retain static-manifest update checks, independent SSH proxy settings per connection, and complete SSH command previews and clipboard copies.

## 1.0.3-beta.2

### Changed

- Configure SSH proxies independently for each connection in Connection → SSH over proxy, with System, SOCKS5, HTTP, and Off modes. Existing global SSH proxy settings migrate to saved connections; global proxy settings now apply only to application updates.
- Check for updates using the latest release's static manifest instead of the GitHub REST API, avoiding its shared-IP API rate limit. Existing release manifests remain supported, and newly published manifests include download URLs and an archive checksum.

### Fixed

- Generate SSH command previews, clipboard copies, and terminal launches through the same path, including proxy transport, forwarding rules, identity files, advanced options, and timeout/keepalive settings.
- Preserve per-connection proxy settings across restarts and connection renames, and remove them when a connection is deleted.
- Explain update request limits more clearly and show an estimated retry time when available.

## 1.0.3-beta.1

### Fixed

- Use English labels for all proxy modes and hide the SSH and update proxy switches when Off is selected. Switching modes preserves the saved switch preferences.
- Add consistent padding inside Port Mapping group drop highlights so the border has comfortable spacing around the expand/collapse arrow, without shifting the header during dragging.

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

## 1.0.1-beta

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
