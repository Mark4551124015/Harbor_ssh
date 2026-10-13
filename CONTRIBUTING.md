# Contributing

Harbor is developed with assistance from OpenAI Codex. Contributions should explain their behavior, how they were verified, and any changes to SSH configuration or local data.

Use Flutter 3.38.9 from `.fvmrc`. Install dependencies with `flutter pub get --enforce-lockfile`, then run:

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub --coverage
python3 -m unittest discover -s scripts/tests -v
```

Use fictional hosts and temporary directories in tests; do not commit private keys, host configuration, credentials or signing certificates. Add regression tests for SSH lifecycle, persistence and interaction changes. Packaging and workflow changes should also pass the checks in `.github/workflows/ci.yml`.

Harbor is licensed under the Apache License 2.0; see [LICENSE](LICENSE).

Private development notes (`docs/`, `notes/`, `dev-notes/`) and local backups (`.local-only/`) are excluded from version control. Keep public usage instructions in `README.md` and `README_zh.md`, and contribution instructions in this file; the two README files are expected to stay in sync.

Code, comments and commit messages are written in English. `README_zh.md` is the only maintained translated document; `lib/settings.dart` additionally carries Chinese search keywords so settings stay findable in Chinese.

## Project layout

- [Application and SSH state](lib/main.dart)
- [Theme and interface components](lib/harbor_ui.dart)
- [Settings and preferences](lib/settings.dart)
- [Key management](lib/key_management.dart)
- [Interaction and SSH regression tests](test/)
- [Native Windows application](windows/Harbor.Windows/)
- [Windows configuration and OpenSSH services](windows/Harbor.Core/)
- [Windows regression tests](windows/Harbor.Core.Tests/)

## Windows development

Use the .NET 10 SDK on Windows. The C# / WinUI 3 app is independent of Flutter and
the macOS runner. Keep Windows UI, processes, persistence and build configuration
under `windows/`; changes to shared assets or the macOS application need their own
review and verification. Keep the two public README files in sync.

```powershell
.\windows\build.ps1 -Task Test
.\windows\build.ps1 -Task Smoke
.\windows\build.ps1 -Task Publish
```

Core tests use temporary files and fictional hosts. OpenSSH integration tests resolve
config with `ssh -G`, generate disposable test keys and connect only to loopback test
listeners. The UI smoke test renders the workbench and five feature pages in both
themes, exports workbench/settings PNG previews, and checks interrupted page/group
animations, native blur reveals and reduced motion with temporary configuration.
Run it in an interactive Windows desktop; it
does not connect to servers or read the user's SSH configuration. Windows CI runs
the core tests and publishes the x64 preview separately from macOS CI.

Review lifecycle changes for ownership, bounded diagnostics and cleanup. Always use
`ProcessStartInfo.ArgumentList`; command previews are PowerShell-quoted text only.
The config store checks for external edits, writes atomically and preserves a backup.
Do not flatten complex SSH configuration into the editable host model.

The in-app mark comes from `assets/brand/harbor-mark.png` and the Dock icon source is `assets/Harbor Terminal Icon.png`. Regenerate the macOS icons with `python3 scripts/generate_app_icon.py`, which needs Pillow, NumPy and SciPy. The classic `AppIcon.appiconset` uses a single Dock icon; the interface theme and the application icon are independent settings.

Regenerate the README screenshots with `flutter test tool/readme_previews.dart` on macOS. The tool uses fictional data and never reads user configuration.
