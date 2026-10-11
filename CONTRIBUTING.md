# Contributing

Harbor is developed with assistance from OpenAI Codex. Contributions should explain their behavior, how they were verified, and any changes to SSH configuration or local data.

Use Flutter 3.38.9 from `.fvmrc`. Install dependencies with `flutter pub get --enforce-lockfile`, then run:

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub --coverage
python3 -m unittest discover -s scripts/tests -v
```

Use fictional hosts and temporary directories in tests; do not commit private keys, host configuration, credentials or signing certificates. Add regression tests for SSH lifecycle, persistence and interaction changes. See [release preparation](docs/releasing.md) before changing packaging or workflows.

The project license is pending the maintainer's decision; no license is implied by this file.
