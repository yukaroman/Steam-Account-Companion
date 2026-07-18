# Releasing

Release artifacts contain executable code but must never contain imported
accounts, backups, signing credentials, Team IDs, or local configuration.

## Common checks

```bash
flutter pub get
flutter analyze
flutter test
git diff --check
```

Confirm the version in `pubspec.yaml`, `CHANGELOG.md`, and the Settings about
copy. Review `SECURITY.md`, `PRIVACY.md`, and `NOTICE.md` when data handling or
protocol sources change.

## iOS personal-device build

```bash
cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig
# Set DEVELOPMENT_TEAM locally.
flutter run --release -d <device-id>
```

For an archive/IPA, use the appropriate Apple distribution identity and
provisioning method:

```bash
flutter build ipa --release
```

An Apple Development-signed IPA is intended only for registered personal test
devices. App Store/TestFlight distribution needs App Store Connect setup and
distribution signing that are intentionally not stored in this repository.
On first side-load, iOS may require explicitly trusting the developer under
Settings → General → VPN & Device Management before the app can launch.
Development profiles also expire and must then be rebuilt and reinstalled.

## Android personal test APK

```bash
flutter build apk --release
```

Without `android/key.properties`, this uses the local Debug key so the APK can
be side-loaded for testing. Do not publish that APK.

## Android store signing

Create a private keystore, then copy `android/key.properties.example` to
`android/key.properties` and fill all four fields. Both the properties file and
common keystore extensions are ignored by Git.

```bash
flutter build appbundle --release
```

Back up the store keystore separately. Losing it can prevent future updates.
Never attach it to an Issue, commit, CI log, or source release.

## Public source release

1. Run a current secret scanner against the working tree and Git history.
2. Verify the public branch no longer contains superseded sensitive history.
3. Create the repository without pushing local build artifacts.
4. Enable private vulnerability reporting and branch protection.
5. Push the clean default branch and create a signed `v0.1.0` tag when ready.
6. Attach only deliberate binaries plus checksums to the GitHub Release.

Real-account Auth V2/mobileconf testing is a separate manual acceptance gate;
never record credentials, raw responses, or request headers while testing.
