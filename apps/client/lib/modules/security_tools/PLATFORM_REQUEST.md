# Text cryptography API request — ready for maintainer approval

Status: proposal only. No platform/dependency edits have been made. The module
API has no cryptographic service and the import gate deliberately prevents direct
package imports. Do not weaken that gate or implement cryptographic primitives
inside the module. User confirmed old Cipher/EV1/CryptoJS compatibility is not
needed. A credential vault is outside this extension.

## Exact requested scope

1. Add `apps/client/lib/modules/module_text_crypto.dart` with a small bounded,
   asynchronous text-only API and export its public types from `module_api.dart`.
2. Add the maintained `cryptography` package to the client pubspec and locked
   resolution; use existing `crypto` for SHA-256/SHA-512 as appropriate. No plugin,
   permission, network or platform channel is needed for this text-only service.
3. Add platform API tests and document the API in `docs/18-module-kit.md`.
   Preserve all existing Module Kit import/architecture enforcement.
4. Consume only that API from this module's new encrypt/decrypt and hash screens.
   No other module, record schema, rollout, version or global guide changes.

## Proposed contract

- `encryptText(plaintext, passphrase)` / `decryptText(envelope, passphrase)`;
  a new versioned Nex envelope with explicit algorithm identity, strict canonical
  parsing and fixed, bounded parameters. Do not autodetect legacy formats.
- AES-256-GCM via the library, fresh secure random 16-byte salt and 12-byte nonce
  per message, 16-byte authentication tag, version/algorithm header authenticated
  as additional data. Never release plaintext before successful authentication.
- PBKDF2-HMAC-SHA256, 600,000 iterations, 256-bit derived key. This is a proposed
  conservative baseline informed by OWASP; benchmark latency on supported devices
  before owner approval. The envelope cannot request attacker-controlled work
  factors. Do work away from the UI isolate and limit concurrent operations.
- UTF-8 plaintext <=16 KiB and bounded passphrase/envelope lengths checked before
  expensive work; no implicit Unicode normalization or whitespace trimming.
  Set explicit password guidance without inventing a strength certification.
- `hashText(text, algorithm)` with SHA-256/SHA-512 and exact validated hexadecimal
  comparison. A matching hash is not proof of sender identity or password safety.
- No persistence, draft, telemetry, logs or secret history. Screens clear state
  on focus loss and ignore stale async completion after clear/disposal/edits.
  Explicit copies retain the existing OS clipboard limitation. No memory
  zeroization or screenshot protection promise.

## Acceptance checks before delivery

Known-answer/library vectors; independent round-trip fixtures; nonrepeat salt and
nonce; wrong passphrase; tampered header/salt/nonce/tag/ciphertext; malformed,
truncated, oversized or unsupported envelopes; invalid Unicode; parameter bounds;
secure RNG failures; no partial plaintext; background/disposal/race cancellation;
SHA vectors and strict comparison. Full analyzer, Module Kit, client suite and
FA/EN, light/dark, compact/large-text UI review remain required.

## Primary sources checked 2026-11-16

- https://pub.dev/packages/cryptography
- https://pub.dev/documentation/cryptography/latest/
- https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html
- https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html

This proposal is not an assertion that adding a library alone makes a vault safe;
key custody and secure persistent storage are separate platform requirements.
