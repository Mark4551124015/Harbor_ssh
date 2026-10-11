# Changelog

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
