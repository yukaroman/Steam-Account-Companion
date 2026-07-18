# Privacy

Last updated: 2026-07-18

Steam Account Companion is a local-first personal application. This document
describes the behavior of the open-source project; a distributor of a modified
build is responsible for documenting any additional collection or services.

## Data handled by the app

Depending on what the user imports, the app may process:

- Steam Guard `shared_secret` and `identity_secret`;
- Steam account name, SteamID, authenticator device identifiers and recovery
  codes;
- Steam login Session cookies, access tokens and refresh tokens;
- an optional imported Steam password, or one the user explicitly chooses to remember after in-app login;
- encrypted backup contents and the user-provided backup password.

These values are used to generate Steam Guard codes, display account metadata,
and communicate with Steam confirmation services.

## Local storage

Account records are stored on the user's device. Local AES-GCM encryption is
enabled by default, with master-key material stored through platform secure
storage. The user may explicitly disable local encryption; in that mode,
sensitive account payloads may be readable on disk.

Encrypted `.sacbak` files are created only when the user starts an export. The
user chooses where those files are stored or shared.

## Network communication

The project has no project-operated backend, analytics, advertising, telemetry,
or crash-reporting service.

When the related feature is used, the app communicates directly with Valve
services, including:

- `api.steampowered.com` for Steam server time and access-token refresh;
- `login.steampowered.com` for Auth V2 device checks;
- `steamcommunity.com` for mobile confirmation lists and decisions.

Those requests are governed by Valve's own terms and privacy practices.

## User responsibility

Do not submit real account data to GitHub Issues, pull requests, CI logs or
public test fixtures. If a secret may have been exposed, revoke or rotate it
through an appropriate Steam recovery flow.

For security reporting instructions, see [SECURITY.md](SECURITY.md).
