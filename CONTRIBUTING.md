# Contributing

Steam Account Companion is an experimental, security-sensitive project.
Contributions are welcome, but changes that handle account material require
extra care.

## Before opening a pull request

1. Do not use real Steam account data in code, fixtures, screenshots, logs,
   Issues or pull requests.
2. Keep secrets out of presentation models, analytics and exception messages.
3. Add or update synthetic tests for protocol, storage and migration changes.
4. Run:

   ```bash
   flutter pub get
   flutter analyze
   flutter test
   ```

5. Update README, SECURITY or protocol provenance when behavior changes.
6. Do not commit personal Apple signing IDs. For local iOS device builds:

   ```bash
   cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig
   # edit DEVELOPMENT_TEAM in Local.xcconfig (gitignored)
   ```

## Pull requests

- Keep each pull request focused.
- Explain user-visible behavior and security trade-offs.
- Describe how the change was tested.
- Clearly identify code or behavior adapted from another project and preserve
  its license and attribution.

By contributing, you agree that your contribution is licensed under this
repository's GNU General Public License v3.0.

## Security reports

Do not open a public Issue for an exploitable vulnerability or include real
secrets in a report. Use GitHub private vulnerability reporting as described in
[SECURITY.md](SECURITY.md).
