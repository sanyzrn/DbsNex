# Note-summary compression — 2.6.1

## Problem and scope

Some long multipart notes were returned almost in full, with headings and
wording cleaned up instead of substantive compression. Many other notes were
already summarised well. This change stays within note summarisation; bookmark
descriptions, the home brief, translation, source text and summary persistence
keep their existing contracts.

## Policy

- For expansive prose, ask for roughly 30–40% of the original length, retaining
  decisions, owners, actions, dates, figures, units, qualifications, conditions,
  exceptions and consequential final sections. This is a target, never a quota.
- Group related requirements and summarise the purpose of sample messages and
  examples. Do not mechanically copy every source heading or cut off output.
- Consider a compression retry only for substantial, prose-heavy text with a
  near-full-length, high-overlap answer. Short notes, compact lists/tables and
  numeric records are excluded by conservative lexical checks. Cross-language
  length differences alone do not trigger it. These checks cannot measure
  semantic density or establish completeness.
- Truncation, numeric errors and compression share **one** additional attempt.
  A successful first answer does not receive a routine review request.
- If a quality-only retry fails, is empty/incomplete, invents numbers, drops
  figures retained by the first answer, or is not shorter, keep the first usable
  answer and clear the retry's failure state. A repeated error without any
  usable answer is still rejected, preserving any previously saved summary.
- Send the full unchanged source on each attempt. Skip a local quality retry
  when its longer prompt would exceed the on-device input budget.

## Regression samples and limits

`packages/ai/test/cloud/fixtures/note_summary_samples.dart` adapts the recovered
eight-topic Nex task: Refresh/Timeline, sheen, Untagged, Paste, recurring UI,
Caption, Urgent, Daily Nudge, and the final conditional release gate. The lost
conversation's full original and original unwanted output were not available;
the fixture is explicitly **not** presented as a verbatim recovery.

The hand-authored compact candidate has 1,000 characters versus 2,696 in the
source (62.9% reduction, trimmed strings). It retains all eight topics, the
conditional release gate, the non-confirmed ۲۰ آبان target, user consent and
the local Daily Nudge fallback. Tests use simulated provider replies to verify
request routing, retry ceilings, candidate selection and failure behaviour;
this ratio is **not a live-model benchmark**. Source-level instructions and
numeric guards do not prove every relationship or negate the need to assess
the chosen model's output.

Additional cases cover English prose, short/dense notes, long compact lists,
numeric records, a different output language, optional-retry failures, and
the local context boundary. Existing numeric, truncation, persistence and
bookmark regressions remain in `note_summary_test.dart`.

## Validation

Flutter 3.35.5 / Dart 3.9.2, matching `.fvmrc`:

- `flutter test --no-pub test/cloud --reporter expanded`: **217 passed**,
  including 17 new compression/fallback regressions. The host's SQLite runtime
  was linked under its development-library name for the persistence test.
- `dart analyze lib/src/cloud test/cloud`: **no issues**.
- Dart formatting, `git diff --check`, and identical root/bundled release notes
  in both languages checked.

No live API request or Android device test is claimed.
