# Audit follow-up

Updated: 2026-09-25. Latest verified release: **v1.30.0** in
`sanyzrn/DbsNex-releases`. Work stays on **codex/work**; do not create branches,
tag, or publish a release. Current changes are prepared under **v1.40.0**;
the owner requested commit/push and will create the tag after verification.

## Scope agreed with the owner

Finish important fixes only. Token budget is limited. Leave additional design,
feature and feedback-service work for a later session. Do not restart a full
audit or deploy the Telegram worker without a new request.

Sources: `Summary_AUDIT.md`, `Summary_AUDIT - ui.md` on the owner's Desktop,
and `NEX_UX_AUDIT.md`. The older `NEX_RELEASE_AUDIT.md` describes an earlier
release and must not be treated as a list of newly reproduced regressions.

## Implemented in the current working tree

- D1–3, D7–8: acknowledged share queue, transactionally deduplicated captures,
  success only after saving, short attachment filenames, SQLite busy timeout,
  serialized text-draft flush including close during the initial insert.
- D4–6 (partial), D9–11, D21: portable full-library backup share/import;
  streamed media in transfer ZIPs; UTF-8 byte lengths; consistent SQLite
  snapshot followed by compression outside the DB worker; safety backup before
  restore; failed restore requests a service restart; unsafe ZIP paths rejected.
- D12–15: unavailable device-auth explanation/settings link while keeping the
  app locked; discard confirmation; explicit update download; corrected backup,
  reminder and cloud-context descriptions.
- D16: external share copy refuses this app's private files and own provider.
- D18–20 (partial): explicit model reasoning envelopes filtered, known greeting
  prompt echoes rejected, Markdown release notes, translated media fallback
  labels and left-to-right file metadata.
- D23–24 (partial): CI path coverage and AI import boundary strengthened;
  release/source-repository comments and current handoff updated.
- UX already implemented: crop/annotation app swipe-back disabled, crop
  viewport constrained/inset, editor draft guard, stable Send position,
  explicit clipboard paste, filter reset/All state, contain photo previews,
  visible off-state switches, several 48dp targets and accessibility labels.

These are code changes, not a claim that all audit findings or device scenarios
are closed. Keep existing changes; do not redo this list from scratch.

## Required before release — highest priority

1. **Android build and device acceptance.** Local build stopped before code
   compilation because AGP `com.android.application:9.3.2` could not resolve
   from the configured repositories. Dart tests do not compile Kotlin. Obtain
   a successful native build/CI result; do not downgrade build tools blindly.
2. **Real share stress/recovery.** Repeat the 150-share test on Android with
   unique markers, warm/cold launches, simultaneous edits, locked DB and failed
   copy. Verify no loss/duplicates and no false Saved. Test activity recreation,
   process termination and expired content-URI permission: queued metadata does
   not itself preserve the source file's read permission. Verify queue ordering.
3. **Private-file import protection.** Reproduce D16 using file URI, symlink,
   own FileProvider and external storage variants on Android. Current copy
   guard covers app dataDir and own provider; verify all private roots.
4. **Restore/upgrade acceptance.** Test valid/corrupt/legacy backups, reminders,
   recurring items, assistant memory and media on a second sandbox. Test
   restoring the oldest recovery copy at the retention limit. Install over the
   released app with the same identity/signature; verify profile, preferences,
   offline model and lock state. Never uninstall/wipe the owner's emulator.
5. **Native photo gestures.** Verify edge-to-edge Android gestures, large photos,
   crop handles, ratios, rotation, annotation and cancellation in Persian/English.

## Remaining data and reliability work

- **D6 storage amplification:** every backup still copies all media. Design
  deduplication/incremental storage separately with retention and restore tests.
  Measure DB snapshot time and peak memory again on the 400MB audit fixture;
  compression no longer owns the DB worker, but snapshot creation still does.
- Check concurrent media deletion/edit during backup compression; the SQLite
  snapshot alone does not freeze the media directory.
- Add cross-tool ZIP interoperability coverage for Persian metadata; transfer
  export is not equivalent to the full-library backup. Settings, credentials
  and downloaded models remain outside that library archive.
- Define crash-safe persistent drafts beyond normal sheet disposal; failed
  imports/copies can leave staged orphan media. Avoid deleting a file after an
  uncertain database commit until ownership is known.
- **D22:** bounded cleanup for old exported ZIPs, interrupted exports and staging
  files, without removing a file another app is still reading.
- Device-transfer secure-storage/bootstrap behavior and Persian multiline
  selection remain unverified. Reproduce before implementing speculative fixes.

## Deferred UX/localization work

- Permanently denied camera/microphone permission: show Open Settings, not a
  retry loop; confirm longer permission text fits small screens.
- Pinned filters: verify fully opaque backing with Liquid Glass; expose active
  type/state clearly. Improve tag touch targets and card-edge contrast.
- Dark accent-container/banner treatment remains deferred (initial color change
  was rolled back because it broke onboarding label contrast).
- Persian calendar choice, consistent digits/date formatting and terminology;
  localize starter defaults without renaming the user's existing tags.
- Offline assistant: accurate error reason, Retry, remove duplicate sheet handle;
  add focused reasoning/prompt-echo regression tests and review provider variants.
- Voice detail: duration/waveform presentation and empty Copy action.
- Small-screen header density, assistant-settings spacing, crop ratio overflow
  affordance and asymmetric system gesture insets.
- Screen-reader, large-font, high-contrast and RTL acceptance. Native home widget
  targets changed to 48dp but need a clipping check on actual launchers.
- Windows minimum size/context menus and runtime acceptance remain deferred.
- Photo decode/rotate/annotation error cleanup and memory profiling remain open.
- Preserve the owner's intentional hidden card timestamps and detail-action
  layout; design-document disagreements do not authorize reverting them.

## Feedback — explicitly deferred

D17: Telegram relay code already exists in `apps/feedback-worker`; its 9 mocked
tests passed. It is **not deployed** and no real message was sent. Android release
builds can now take repository variable `NEX_FEEDBACK_API_URL`. Future setup
needs Cloudflare deployment plus Worker secrets `TELEGRAM_BOT_TOKEN` and
`TELEGRAM_CHAT_ID`, then the public Worker URL as the release variable. Review
rate limiting/timeouts before enabling. Never commit or print bot credentials.

## Verification record

- Pinned Flutter: `C:\src\flutter-3.35.5\bin\flutter.bat`; use `--no-pub` with
  the existing resolved dependencies. PATH Flutter is a different version.
- Data suite: **151 passed, 13 skipped**. Data and UI analyzers: no issues.
- Client analyzer: no issues on the final working tree, including the
  recovery-copy preservation edit.
- Client full run: **668 passed, 2 skipped, 3 failed** initially. Failures were
  changelog asset completion, an unmocked OS-auth call, and dark onboarding
  contrast. The latter two were corrected; see the final verification below.
- Capture regressions include 150 simultaneous mocked deliveries, duplicate
  delivery, failure reporting and closing before a delayed first insert.
- Backup regressions include unsafe Windows paths, snapshot consistency and
  corrupt-restore preservation. These do not replace Android acceptance above.
- Local logs: `%TEMP%\nex-audit-final-client.log`,
  `nex-audit-final-data.log`, `nex-audit-final-recheck.log`.
- Final focused rerun of changelog, lock privacy, onboarding and backup screens:
  **23 passed**. The previously failing cases pass after the fixes. The whole
  client suite has not been repeated after that focused rerun.
- The owner subsequently requested committing/pushing all changes as 1.40.0
  on `codex/work`. No new branch, tag or Telegram deployment is authorized.

## Next session

Read this file and `git status` first. Finish only the release gates above when
authorized; update this ledger with evidence. Do not call the app release-ready
while the native build/device checks remain outstanding.
