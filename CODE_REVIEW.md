# Code Review

## Pre-open-source audit

Review date: 2026-07-18
Scope: current `0.1.0` source tree

The repository is ready for a source-only Alpha release. No unresolved issue
was found by static analysis, automated tests, release compilation, package
signature checks, or the allowlisted secret scan.

### Findings fixed in the final review

| Priority | Finding | Resolution |
| --- | --- | --- |
| P2 | A malformed mobile-confirmation item could substitute `creator_id` for the required `nonce` / `ck[]` value. | Accept only a real `nonce`; skip malformed entries; add regression coverage. |
| P2 | String values such as `success: "false"` could be treated as an empty successful response. | Distinguish explicit success, explicit failure, missing markers, and invalid markers; add response-shape tests. |
| P3 | A visible Steam time-sync call joining a silent in-flight call did not notify the UI. | Merge notification intent while retaining one network request; add a concurrency test. |
| P3 | A sanitized test account rename left one stale initials assertion. | Update the assertion to the synthetic replacement name. |

Release preparation also added in-app GPL notices, Release-mode log
suppression, Android backup/cleartext restrictions, documented signing paths,
a compact threat model, dependency automation, exact-value secret-scan
allowlisting for synthetic fixtures, and current open-source metadata.

### Verification

| Check | Result |
| --- | --- |
| `flutter analyze` with `flutter_lints 6` | Passed, no issues |
| `flutter test` | 144 tests passed |
| iOS signed Release build | Passed |
| Android Release APK build and v2 signature verification | Passed |
| macOS Release build | Passed |
| Web Release build | Passed |
| `git diff --check` | Passed |
| Gitleaks working-tree scan | Passed; only exact documented synthetic values are allowlisted |

The Android APK produced without `android/key.properties` is intentionally
Debug-key signed for personal side-loading. It is not a store-distribution
artifact.

### Manual acceptance still required

- Complete a real-account Auth V2 login, mobile-confirmation list, accept, and
  reject flow. These unofficial endpoints cannot be fully validated with
  synthetic automated tests.
- Exercise import, biometrics, background/resume, and upgrade preservation on a
  physical Android device. Android compiles successfully, but this audit had no
  Android device available.
- Revisit application-switcher snapshot shielding before use beyond the stated
  personal Alpha threat model.
- Replace the temporary `file_picker` Kotlin compatibility workaround after
  Flutter and the plugin complete their AGP built-in Kotlin migration.

Earlier development reviews were performed against superseded private history.
This file intentionally records only findings and checks that remain meaningful
for the clean public source history.
