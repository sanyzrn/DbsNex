# Security Policy

## Threat model

Nex is local-first. In v1 all data lives on the user's device and never leaves
it. From v2 an optional sync server holds an encrypted-in-transit copy of notes
for the accounts that opt in. The assets we care about, in order:

1. **Note contents and media.** Users capture unfiltered thoughts. Disclosure is
   the worst possible outcome for this product.
2. **Device tokens.** A leaked device token grants full read/write to one
   account's corpus until it is revoked.
3. **Availability of capture.** Capture must work offline and must never be
   blocked by a network or server failure.

## Supported versions

Only the latest tagged release receives security fixes.

## Reporting a vulnerability

Please report privately via GitHub's **Report a vulnerability** button on the
Security tab, or by opening a draft security advisory. Do not open a public
issue.

Please include: affected component (client / backend / packages), the version or
commit, reproduction steps, and the impact you believe it has.

We aim to acknowledge within 72 hours and to ship a fix or a mitigation plan
within 30 days for anything rated high or critical.

## Scope

In scope: the Flutter client, the sync backend, the Dart packages, the release
pipeline, and the signing configuration.

Out of scope: findings that require a physically unlocked device with the app
already open; denial of service against a self-hosted backend the reporter
controls; and missing hardening headers on endpoints that hold no data.

## Handling secrets

The Android upload keystore and its passwords live only in GitHub Actions
secrets. They are never committed. `android/key.properties` and
`*.keystore` are gitignored, and CI release builds fail hard rather than
falling back to the debug key.
