# Security toolbox / جعبه‌ابزار امنیت

## 1. What it does and screens

Offline consumer tools: a random password/passphrase generator, a conservative
textual link inspector, personal account checklists, a short response guide and
a UTF-8 text converter (standard Base64, URL component, Hex).
Home counts only user-confirmed actions, not a security score. The generator
starts hidden and never stores its output. The inspector never opens a link,
contacts a host, resolves a redirect or declares a site safe. Account records
contain an alias and four self-reported states, not credentials or recovery codes.

## 2. Records and versions

Module ID/store namespace `security_tools`. Kind `account`, schema v1:
`{v:1,label:<alias>,checks:{unique,mfa,recovery,sessions}}`.
Alias: nonblank, ≤60 UTF-16 units. Check values: `unknown`, `todo`, `done`,
`unavailable`. Unrecognized/malformed values display as unknown, never completed.
Unknown raw fields and untouched unknown check states survive edits. Unsupported
or malformed records stay visible for explicit repair or confirmed deletion.
No destructive migration is introduced.

Kind `draft`, shared `NexModuleFormDraft` v1 envelope. `account:new` and
`account:<id>` retain alias, status choices, explicitly touched keys and a stable
save ID. A baseline fingerprint prevents stale drafts replacing a changed
record. Back flushes checkpoints, save clears after the final write, read errors
block editing and offer Retry. These noncredential records travel in existing
module backups. Generated secrets and link inputs deliberately have no drafts,
records, telemetry or history.

## 3. Important decisions

- Production entropy comes only from `Random.secure()`. Failure produces no
  result and no fallback. Passwords are 16–64 characters, default 24, sampled
  from the selected alphabet. Rejection sampling requires each chosen class
  without a biased forced-character/shuffle fallback; the attempt count is
  bounded to 128 and fails closed if exhausted.
- Compatibility controls do not rate a person's password. No password checker,
  brute-force time estimate or compliance certificate is advertised.
- Passphrases sample six to eight independent indices with replacement from
  the full 7,776-entry EFF Long Wordlist. Spaces separate words; spelling,
  order and internal hyphens are retained. See WORDLIST_NOTICE.md.
- Generated text is hidden until requested, is not localized/transformed,
  and is removed from page state on app focus loss, route disposal or option
  changes. This is not a guarantee of memory zeroization or screenshot blocking.
  Explicit Copy uses the existing platform clipboard; it may remain there.
- Link input is bounded to 4096 UTF-16 units and never saved. Explicit HTTP(S)
  is required. Ambiguous controls, bidi marks, backslashes and malformed hosts
  are refused. Reports show the full parsed host, never an invented registrable
  domain. Expected-domain comparison is exact, including the full subdomain;
  a trailing DNS dot is normalized. An exact match is not a trust verdict.
- Textual findings cover HTTP, userinfo, international/punycode or encoded
  authority, numeric/IP hosts, unusual ports, redirect parameter hints and
  fragments. Findings are incomplete heuristics; browser parsing may differ.
  No reputation, certificate, DNS, shortened-link or redirect check is implied.
- Account changes use a session write queue and fresh raw-body checks.
  Conflicts retain input and offer saving a new checklist. Confirmed deletion
  has raw Undo guarded against a recreated ID. The shared store has no
  cross-process compare-and-swap; independent external writers are a limit.

- Text conversions are reversible representations, not encryption. Inputs are
  bounded to 8,192 UTF-8 bytes, computed only on explicit action. Standard Base64
  requires canonical padding/pad bits; Hex accepts complete byte pairs and ASCII
  separators, never strips junk. Decoding rejects invalid UTF-8, and encoding
  rejects unpaired UTF-16 surrogates instead of replacing data. URL conversion is
  for one component (plus is not a form-encoded space). A changed input/mode clears
  stale output. Reverse conversion never silently truncates oversized output.
  The screen clears both directions on focus loss/disposal and has no drafts.

## 4. Research (verified 2026-11-16)

- RFC 4648: https://www.rfc-editor.org/rfc/rfc4648.html — Base64 vectors,
  canonical padding and pad bits; strict decoding rather than silently repairing
  damaged encoded input.
- NIST SP 800-63B-4: https://pages.nist.gov/800-63-4/sp800-63b.html
  Length, unique generated credentials, managers and phishing-resistant factors
  inform the design. Verifier rules are not presented as generator certification.
- Dart secure RNG: https://api.dart.dev/dart-math/Random/Random.secure.html
  and https://api.dart.dev/dart-math/Random/nextInt.html — secure source or throw,
  with bounded uniform sampling. The implementation uses the pinned SDK.
- EFF: https://www.eff.org/dice — six-word guidance and the complete long list.
  Data provenance, SHA-256, adaptation and CC BY 3.0 US credit are recorded in
  WORDLIST_NOTICE.md. No EFF endorsement is implied.
- Mozilla phishing guidance: https://infosec.mozilla.org/guidelines/phishing.html
  Inspect full hosts; independently navigate to a known service.
- FBI/IC3: https://www.ic3.gov/PSA/2019/PSA190610 — HTTPS text does not prove
  legitimacy. This tool does not inspect a connection or certificate.
- OWASP MFA and session guidance:
  https://cheatsheetseries.owasp.org/cheatsheets/Multifactor_Authentication_Cheat_Sheet.html
  https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html
  Review recovery/factors/sessions rather than assuming password changes revoke
  every existing session. No TOTP seed is collected or stored here.
- Google compromised-account recovery:
  https://support.google.com/accounts/answer/6294825?hl=en
- FTC phishing and malware:
  https://consumer.ftc.gov/articles/how-recognize-avoid-phishing-scams
  https://consumer.ftc.gov/articles/malware-how-protect-against-detect-and-remove-it
  Practical response steps are adapted without US-only reporting numbers.

## 5. Guide / راهنما

FA: در «تبدیل متن»، قالب و جهت تبدیل را انتخاب کن. این ابزار رمزگذاری امن نیست؛
برای فارسی از UTF-8 استفاده می‌کند. دکمهٔ جابه‌جایی، خروجی را بدون بریدن به ورودی
می‌برد و جهت تبدیل را برعکس می‌کند.

FA: برای ساخت رمز، قالب و طول را انتخاب کن، «ساخت رمز تازه» را بزن و فقط
وقتی لازم است آن را نمایش بده یا کپی کن. کپی ممکن است در کلیپ‌بورد سیستم بماند.
برای لینک مشکوک، متن کامل و در صورت نیاز دامنه‌ای که مستقل می‌شناسی را وارد
کن؛ گزارش فقط نشانه‌های متنی است و بازشدن یا امن‌بودن سایت را تأیید نمی‌کند.
برای پیگیری حساب‌ها، یک نام مستعار بنویس و وضعیت چهار اقدام را خودت مشخص کن؛
رمز یا کد بازیابی ننویس. اگر اطلاعاتی داده‌ای، راهنمای اقدام را بر اساس آنچه
اتفاق افتاده مرور کن و از مسیر رسمی سرویس کمک بگیر.

EN: In Text converters choose a format and direction, then convert explicitly.
This is not encryption. Persian and emoji use UTF-8. Reverse reuses the complete
output and switches direction when the input byte limit permits it.

EN: Generate a password or phrase, reveal only when needed and explicitly copy.
The OS clipboard may retain it. Inspect a suspicious HTTP(S) link without opening
it; optionally compare the full host to a domain you already know independently.
The result does not establish safety. Save only an account alias and your own
checklist states; never enter passwords or recovery codes. Use the response
guide to choose next steps after possible exposure, through official routes.

## 6. Changelog

FA: افزوده شد: تبدیل متن فارسی و انگلیسی با Base64، URL و Hex، جابه‌جایی
ورودی و خروجی و ردکردن دادهٔ نامعتبر؛ بدون ذخیرهٔ محتوا.

FA: جعبه‌ابزار امنیت: رمز و عبارت عبور تصادفی، بررسی آفلاین لینک، چک‌لیست
حساب‌ها و راهنمای اقدام؛ بدون ذخیرهٔ رمز یا صدور تأیید امنیت.

EN: Added UTF-8 Base64, URL component and Hex conversion with reverse reuse,
strict validation and transient input/output.

EN: Security toolbox: random passwords/passphrases, offline textual link
inspection, account checklists and a practical exposure-response guide.

## 7. Platform requests and rollout

Keep Soon until owner device review; availability is unchanged. Integration
changes are limited to registry/plan entries and their catalog-count contract.
The old plan mentioned AES-GCM, hashes and encrypted secret storage.
[Concrete platform request](PLATFORM_REQUEST.md) identifies the exact API,
dependency and tests needing owner approval for text encryption and hashing.
Old site format compatibility was explicitly declined by the owner. Module Kit
exposes neither reviewed cryptographic primitives/key management nor protected
secret storage. These remain explicit platform requests; no home-grown crypto,
plaintext secret database or disguised Base64 encryption is substituted.

Other needed platform capabilities: sensitive clipboard marking plus conditional
expiry, screenshot/recents protection, and audited secret memory/lifecycle hooks.
The current clipboard API cannot promise auto-clear or suppress OS previews.
The module does not scan apps, files, devices or breach databases and does not
configure accounts automatically. No network, OS permissions, new dependencies,
notifications, global versions or release changes are introduced.

## 8. Verification

Pinned Flutter 3.47.9 / Dart 3.13.7, locked dependencies. Commands run from
`apps/client` with `CI=true BOT=true FLUTTER_SUPPRESS_ANALYTICS=true`; the host
SQLite library was built from the repository's existing vendored SQLite source,
outside the repository. No dependency or lockfile changes.

- `flutter analyze --no-pub --fatal-infos`: no issues.
- `dart format --output=none --set-exit-if-changed` on the six Dart files changed
  in this extension: 6 files, zero changes.
- `flutter test --no-pub test/modules/security_tools --reporter expanded`:
  79 passed (16 pure logic, 4 repository, 11 widget flows, 48 layout cases).
- `flutter test --no-pub test/module_kit_test.dart test/module_preview_test.dart
  test/modules_test.dart test/modules/security_tools --reporter expanded`:
  146 passed, including architecture, catalog, namespace and module UI contracts.
- `flutter test --no-pub --reporter expanded`: full client suite, 3,841 passed, 4 existing skips, zero failures.
- `git diff --check`: clean.

Coverage includes entropy failure, full-wordlist sampling, invalid/ambiguous
URLs, exact host comparison, stale-result removal, ephemeral secrets/clipboard,
strict codec vectors/Unicode/errors/reverse, draft read/write/cleanup failures, stable save IDs, stale edits, raw Undo and
unknown-field preservation. Layout checks cover FA/EN, light/dark, 390×844 and
320×640 with 2× text and reduced motion. Review renders use synthetic records,
never real account credentials; generated text stays hidden.

| Screen | Review image |
| --- | --- |
| Home, FA dark | [Home](review/home_fa_dark.png) |
| Generator, FA dark | [Generator](review/generator_fa_dark.png) |
| Generator, EN light | [Generator](review/generator_en_light.png) |
| Text converter, FA dark | [Converter](review/codec_fa_dark.png) |
| Text converter, EN light | [Converter](review/codec_en_light.png) |
| Link inspection, FA dark | [Link](review/link_fa_dark.png) |
| Checklist, FA dark | [Checklist](review/account_fa_dark.png) |
| Response guide, EN light | [Guide](review/incident_en_light.png) |

No Android device, APK build, TalkBack session or performance trace is claimed.
