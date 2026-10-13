# Windows EXE installers

Build requirements: Windows, .NET 10 SDK, and Inno Setup 6.7 or later.

Generate the two application packages in a new output directory:

```powershell
./windows/package.ps1 -OutputDirectory windows/artifacts/release
```

Compile both installers from those verified ZIP packages:

```powershell
./windows/installer/build.ps1 -PackageDirectory windows/artifacts/release -Compiler 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe'
```

The compiler also accepts the local ignored tool at `.local-only/toolchain/inno/compiler/ISCC.exe`, or `ISCC.exe` on PATH. The build reads the app version from the published assembly and writes installers and SHA256 checksums to `windows/artifacts/release/installers/`.

- `self-contained`: includes .NET; no separate .NET installation required.
- `framework-dependent`: checks for the .NET 10 x64 runtime before installing. If missing, the interactive installer offers to open Microsoft's download page.

Both installers install for the current user, support a custom destination and shortcuts, and register an uninstaller. Application files live in the install directory's `app/` subfolder. Upgrades replace only that managed payload; SSH configuration and Harbor user preferences are stored separately and are not removed by uninstall.

Generated packages, compiler downloads, temporary staging folders, and signing keys are ignored by Git. Installer scripts are tracked. The EXE installers are unsigned unless a signing step is added separately.
