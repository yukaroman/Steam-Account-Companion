# Security Policy and Design Notes

Steam Account Companion is a security-sensitive, experimental application. It
uses platform secure storage and encrypted account persistence, but it has not
received an independent security audit. Use real Steam account material only
after reviewing the documented trade-offs and keeping a working recovery path.

## Supported versions

Only the latest commit on the default branch and the latest published release
receive security fixes. Older builds may contain known protocol or storage
issues.

## Reporting a vulnerability

Use GitHub private vulnerability reporting from the repository's **Security**
tab. Do not open a public Issue for an exploitable vulnerability, and never
include a real maFile, `.sacbak`, Cookie, token, password, recovery code or
generated Steam Guard code.

If a real secret may have been exposed, revoke or rotate it first; a project
maintainer cannot recover or safely handle exposed Steam credentials.

## Sensitive values

Treat all of the following as secrets:

- `shared_secret` and `identity_secret`
- login cookies and session state
- OAuth and refresh tokens
- recovery codes
- device identifiers used by Steam authentication (`device_id`, authenticator serials)
- imported maFile or SteamTools export contents

## Product decision: optional at-rest encryption

This is a **personal / local-first** companion. At-rest encryption of account payloads is **recommended and on by default**, but **not mandatory**.

| Mode | Behavior |
| --- | --- |
| **Default: encryption on** | Account payloads are sealed with AES-256-GCM. AAD binds each blob to its internal account id. Master key material is stored through platform secure storage. |
| **User opt-out: encryption off** | Account payloads may be stored as local JSON (including secrets). The settings UI must state clearly that secrets become readable on disk / in local storage. |

Rules for this decision:

1. **Default remains encrypted.** Do not ship with encryption off by default.
2. **Opt-out must be explicit** (user toggle). Never silently disable encryption during migrations or bugs.
3. **Face ID / biometrics are independent** of at-rest encryption. Turning biometrics off must not force plaintext storage, and turning encryption off must not require biometrics.
4. **Presentation layers do not receive raw secrets by default.** Narrow, owner-initiated exceptions are documented below: the account-details reveal flow and prefilling an obscured password after the user has chosen to remember it.
5. **Reversible migration** between encrypted and plain payloads is allowed when the user changes the setting; decrypt-then-rewrap must keep account-id binding when re-enabling encryption.

Recommended production path when encryption is on:

1. Generate a random master key (non-exportable when the platform allows).
2. Protect the master key with iOS Keychain / Android Keystore access controls.
3. Encrypt each account payload with AES-GCM (or equivalent authenticated encryption).
4. Keep nonces unique and persist the authentication tag with each payload.
5. Never expose decrypted secrets to ordinary widgets, analytics, crash
   reporters, or Release-mode logs.

Cryptography must use reviewed platform or package primitives. Do not implement AES manually.

## Product decision: paste import shows plaintext (prototype)

The import screen’s JSON paste field uses **`obscureText: false`** so multi-line maFile / lightweight exports are easy to inspect while pasting.

This **conflicts** with the general “no full secrets in UI” rule below, and is an explicit **prototype / personal-use** trade-off:

1. Paste is for local import only; buffers and clipboard are wiped after success or failure.
2. File import remains available without showing body contents in a field.
3. The owner has explicitly retained this behavior for the personal-use Alpha.
   Re-evaluate masking or removing paste before broader distribution.

## Product decision: owner can reveal imported secrets in account details

For a **personal / single-user** companion, imported account material must be inspectable after import (SteamTools / SDA style), not only during paste.

Rules:

1. **Default still hidden.** Token page and account metadata sheet do not show `shared_secret`, `identity_secret`, recovery/`revocation_code`, or password until the owner explicitly confirms. Status chips may say whether a recovery code exists without showing it.
2. **Explicit reveal only.** Account details → “确认后查看密钥” → confirmation dialog → then show Base64 secrets, recovery code (if stored), and password (if stored), each copyable.
3. **Easy hide.** “隐藏密钥” clears the revealed view; reopening the sheet starts hidden again.
4. **Lock clears overlays.** When the app locks (manual or auto-lock), open account-detail sheets and dialogs are dismissed so revealed secrets cannot sit above the unlock gate.
5. **No ambient display.** Secrets must not appear in account switcher chips, logs, analytics, or crash reports.
6. **Not a multi-user vault.** This is acceptable only because the product assumes the device owner is the sole user; if multi-user or shared-device support is added, require real biometrics / passcode before reveal.

The login sheet may prefill a previously remembered password into an obscured password field. That value must not be logged or surfaced through errors, and it must remain hidden unless the owner explicitly uses the field's visibility control.

## Absolute prohibitions (always)

Regardless of the encryption toggle, secrets must never:

- be committed to Git, issues, CI logs, or test fixtures as real account material;
- appear in production logs, debug screens, analytics, or crash reports;
- be copied into shared, unencrypted cloud backups without an explicit, documented export flow;
- be shown in full in the UI **by default** — only via documented owner-initiated flows (paste import; account-details reveal above; explicit visibility control for an obscured remembered-password field).

Public unit tests may use **synthetic** demo secrets only.

## Face ID / lock screen

The Settings Face ID toggle enables the unlock gate on cold start and auto-lock.
On iOS/macOS/Android the unlock page uses **`local_auth`** (system Face ID /
fingerprint / device credential). When the gate is enabled, unavailable,
cancelled or failed system authentication does not fall through to an
unauthenticated tap. Web does not offer this gate. Trade/login confirmations do
not re-prompt system authentication.

## Encrypted backup (`.sacbak`)

Personal device migration / offline copy:

1. Settings → **导出加密备份** → choose a **backup password** (min 8 chars; independent of Face ID and of the at-rest master key).
2. App writes a `.sacbak` JSON envelope: PBKDF2-HMAC-SHA256 (210k iterations) → AES-256-GCM over a payload of full account records.
3. Settings → **从备份恢复** → pick file → enter the same password → accounts are **merged** (same id overwrites).
4. Restore **must not** change the user's "encrypt at rest" preference; restored blobs are re-wrapped with the current cipher setting.

Wrong password or tampering fails closed (authenticated decryption). Never commit real `.sacbak` files or backup passwords.

## Logging rules

Production logs must not include request headers, response bodies, cookies, tokens, account exports, confirmation parameters, or generated authentication codes. Errors exposed to the UI should use sanitized domain error types (no payload dumps).

## Import lifecycle

Imported files must be validated before use, copied only when necessary, and deleted from temporary storage on success, cancellation, or failure. Debug builds follow the same cleanup rules.

When encryption is **on**, encrypt the imported payload before long-term persistence.
When encryption is **off**, still avoid temporary plaintext copies lingering after import; write once to the account store and wipe temps.

## Release gates

Before any real-account build:

- review [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) and current dependencies;
- keep fixed, public Steam Guard test vectors (synthetic keys only);
- verify master-key load failures can retry without process restart;
- test device lock / biometrics only if those features are enabled;
- verify backup and restore cannot **silently** weaken the user’s chosen encryption setting;
- confirm current Steam protocol behavior and distribution requirements;
- if encryption opt-out remains, reconfirm that the UI risk copy is accurate and hard to miss.

Please do not report real account secrets in an issue. Revoke or rotate any
secret that may have been exposed.
