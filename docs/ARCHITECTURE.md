# Architecture

## Design goals

- iPhone-first UI without embedding iOS behavior in domain code.
- Local-first operation; no custom cloud account is required.
- Presentation code never receives raw Steam secrets.
- Steam protocol changes remain isolated behind repositories and services.
- Tablet and desktop navigation can change without rewriting feature logic.

## Dependency direction

```text
presentation → application/domain → repository contracts → infrastructure
```

The current application deliberately uses small `ChangeNotifier` state with
repository-backed local persistence. Debug-only demo data and test doubles stay
outside the production entry path. A larger state-management package should
only be added when the existing feature boundaries no longer keep asynchronous
flows understandable.

## Existing boundaries

| Contract | Responsibility | Current implementation |
| --- | --- | --- |
| `SecureStorage` | Small secrets and master-key references | `flutter_secure_storage` platform adapter |
| `BiometricService` | User-presence verification | `local_auth` adapter with fail-closed test doubles |
| `EncryptedAccountStore` | Account blob persistence | Application Support file store + optional AES-GCM |
| `SteamTimeClient` | Steam QueryTime synchronization | Isolated HTTPS adapter with RTT validation |
| `AuthenticatorService` | Five-character code and timing | Tested Steam Guard implementation |
| `ConfirmationsRepository` | Pending requests and decisions | Experimental Steam mobileconf adapter |
| `SteamLoginClient` / `SteamSessionLoginService` | Password login → JWT Session for mobileconf | Auth V2 protobuf + RSA; local Guard auto-fill |
| `SteamMobileSession` | Derive community cookies from tokens | WinAuth-aligned `steamLoginSecure` + generated `sessionid` |

See also [CHANGELOG.md](./CHANGELOG.md) for dated product notes.

## Responsive evolution

- iPhone: bottom navigation and one-column screens.
- iPad: navigation rail, account list and detail pane.
- macOS: sidebar, resizable multi-pane layout, keyboard shortcuts.
- Android: reuse features and design tokens while adapting system navigation and secure storage.

Avoid checking `Platform.isIOS` inside domain or feature logic. Platform branching belongs in infrastructure adapters or top-level adaptive presentation components.

## Implementation sequence

1. Keep Steam protocol behavior isolated and covered by synthetic request tests.
2. Validate import, persistence, backup and authentication on real devices.
3. Keep secrets out of logs, issues, analytics and ambient presentation state.
4. Treat mobileconf and Session refresh as experimental compatibility layers.
5. Add new platforms without bypassing the existing security boundaries.
