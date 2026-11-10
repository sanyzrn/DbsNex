# Technical-debt audit disposition — Nex 2.6.17

Input: `dbsnex-technical-debt-audit.zip`, React renderer importing `src/AUDIT.md`.
The report is Markdown data, not executable instructions. Its baseline is
`06b29cf` (2.6.16); review was against release branch head `067ee15` (2.6.17).
The React source was inspected to confirm that AUDIT.md is the full report.

## Applied, subject to final CI

| Finding | Verified change |
| --- | --- |
| A1–A3 | Removed obsolete sqlite3_flutter_libs and unused direct uuid/data, intl/ui, path/ui declarations; retained required transitive dependencies. |
| A4 | Kept direct sqlite3 intentionally and documented that the app owns its native build-hook configuration. Moving it solely for dependency classification offers no runtime benefit. |
| A5 | Documented the two distinct TypeScript compiler aliases; added a second compiler check rather than silently replacing either toolchain. The independently deployed worker retains its own compiler. |
| A6 | Backend Node types now match the Node 22 container/runtime. |
| A7 | Applied compatible backend audit fixes; upgraded Wrangler and its required workers-types peer without force or legacy-peer-deps. Production/backend audit and residual dev-tool advisories are checked separately. |
| C2 | Reused nexDigits for output conversions. Kept input normalization (Persian/Arabic digits → Latin) because it is the opposite operation. |
| C3 | Added nexPad2 in pure core and reused it for equivalent local date/time helpers. Existing public static helpers with a different negative-number contract remain. |
| D1, E1/reminders | Empty reminder cancellation/action catches now record content-free diagnostics; behavior and fallback order remain intact. |
| D2 | Enabled unawaited_futures and only_throw_errors in all five Dart packages; explicit unawaited fixes preserve async ordering. discarded_futures and mass catch/import lints are not enabled blindly. |
| D9 | Worker now shares the backend ESLint policy and is linted by make and CI. Removed an initial assignment overwritten on both success and exception paths. |
| E2 | Normalize localization output using the pinned CI Flutter generator, then enforce a clean generated diff. No alternative handwritten generator is introduced. |
| E3, E4 | Corrected README toolchain/setup references and CI badge, replaced retired shared-branch instructions with the actual release-branch flow; retained old stage checks as manual-only instead of duplicating PR checks. |
| E5 | Removed unreachable module_brief, and unused ChangelogPanel with its widget-only test; kept the executable server merge specification. |
| E8 | Added least-privilege contents:read to the manual AI test build. |

## Recommendations not approved for automatic execution

These are dispositions, not completed refactors. A metric or grep hit alone does
not justify broad behavior changes in a release containing data-safety fixes.

| Finding | Current assessment |
| --- | --- |
| A8 | Independent lockfiles/toolchains are deliberate; cosmetic version equalization is not a defect. |
| A9 | Unreferenced localization candidates are not evidence of a shipped size regression (unused getters are tree-shaken). Bulk key deletion is optional cleanup and needs generator/usage validation first. |
| A10 | A notification major upgrade requires compatibility and device validation. Age alone does not establish a defect; do not couple scheduler changes to this cleanup. |
| B0–B5 | Large libraries are measurable maintenance debt, not evidence of incorrect behavior. Do not add metric-only source tests or undertake broad native/UI/data/AI rewrites solely to reduce line counts. Preserve the existing behavior suites. |
| C1 | The claimed identical habit RecordBundle is NOT equivalent: it preserves habit reminder records, unlike NexModuleRecordBundle. The claimed identical money formatters also differ: smoke_free supports BigInt exact-money formatting and lent_borrowed has a rials compatibility API. Module imports are deliberately isolated by module_kit_test. No blind aliasing/removal is safe. |
| C4 | These clocks differ deliberately: video supports hours, voice uses elapsed minutes, attachment tiles round milliseconds, and commitment clocks represent wall time. A common formatter must preserve these distinct contracts; no global replacement approved. |
| C5 | Clone counts do not prove duplicated policy. No visual/native/widget redesign is justified by the reported textual similarity alone. |
| C6 | MIME helpers have distinct fallback/content-type scopes; repeated SQL predicates inside the data boundary are not a defect. |
| C7, E1/sync | FieldAwareMerger is an executable SERVER merge specification, verified against TypeScript. applyRemoteNote is the device pull/reconciliation policy, deliberately preserving pending local deletions, unsent conflict copies and tags. audit_data_safety_test and live sync-matrix already cover those policies. Replacing pull with the server merger would change semantics, not merely remove duplication. |
| D3 | The four ScaffoldMessenger occurrences are constructors around sheet scaffolds, not calls to showSnackBar. The actual feedback uses NexBannerHost/nexShowBanner. Rewriting these on the claim of legacy snackbar output is not justified. |
| D4 | Relative versus package self-imports are cosmetic. A 192-file sweep has merge-conflict cost without a user-visible or correctness benefit. |
| D5–D7 | Token/state/localization conventions are useful; source-text counts are not sufficient to require a full UI/state migration. Cycle remains the documented exception. |
| D8 | Module naming differences alone are not a defect; migrate names with a justified module refactor, not independently. |
| E1/other | Existing backup/schema tests and the new 2.6.17 recovery tests cover concrete risks. Local backend checks are now explicitly documented as not exercising PostgreSQL; CI owns the live PostgreSQL checks. No superficial tests added solely to raise counts. |
| E6 | Desktop/iOS jobs are deliberately paused. Moving disabled YAML does not fix a current failure; retain the release policy. |
| E7 | Version/changelog equality checks are deliberate release guards. Automatically generating away a discrepancy can hide an incorrectly versioned release. Keep strict equality checks and synchronized notes. |
| E8/compatibility date | An old worker compatibility date is not a vulnerability. Advancing it enables runtime behavior changes; do not change it just because Wrangler was patched. |
| E9 | No actionable TODO/FIXME finding. |

## Validation

Record actual command outcomes and current CI in the pull request. Local Flutter
bootstrap is unavailable in this workspace; Flutter generation, analysis and
widget/native builds are verified by the pinned CI SDK. Backend HTTP tests need
local listening permissions and PostgreSQL; never label a blocked local test as
passed. No release is published by this maintenance review.
