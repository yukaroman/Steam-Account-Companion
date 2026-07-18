# Threat model

This is a compact model for the personal-use `0.1.x` release. It is not an
independent security audit.

## Assets

- Steam Guard `shared_secret` and `identity_secret`
- access/refresh tokens, cookies, optional remembered password
- recovery code, SteamID, account name, and authenticator device identity
- encrypted backup contents and backup password

## Trust boundaries

| Boundary | Assumption |
| --- | --- |
| Device storage | The OS sandbox and platform secure storage are available and not already compromised. |
| User interface | The device owner is the only intended user; explicit reveal and paste-import flows may show secrets. |
| Imported files | Input is untrusted, size-limited by normal platform picker behavior, parsed locally, and never executed. |
| Network | Requests go directly over HTTPS to Valve/Steam endpoints; the project operates no backend. |
| Build/source | Public fixtures are synthetic; signing keys, Team IDs, account exports, and local config stay outside Git. |

## Main threats and controls

- **Repository or log leak:** ignore sensitive file types, use synthetic
  fixtures, sanitize domain errors, and suppress exception details in Release.
- **Offline file theft:** AES-256-GCM is enabled by default and binds blobs to
  account IDs; users may explicitly opt out for this personal app.
- **Stolen unlocked device:** optional system-auth gate and manual lock are
  available. This is not protection against an already compromised OS.
- **Tampered local data/backup:** authenticated encryption fails closed.
- **Network interception:** cleartext Android traffic is disabled; Steam
  requests use HTTPS. Certificate pinning is intentionally not implemented.
- **Protocol changes or malicious responses:** response shapes and success
  markers are validated, but Auth V2/mobileconf are unofficial and may break.

## Accepted limitations

- Paste import is visible plaintext by explicit product decision.
- Account owners can explicitly reveal stored secrets.
- Android/iOS application-switcher snapshot shielding is not implemented.
- A user who disables at-rest encryption accepts readable local account JSON.
- No guarantee is made against rooted/jailbroken devices, runtime
  instrumentation, screen recording, clipboard readers, or compromised builds.

Any expansion to shared-device, cloud-sync, telemetry, or project-operated
backend use requires revisiting this model.
