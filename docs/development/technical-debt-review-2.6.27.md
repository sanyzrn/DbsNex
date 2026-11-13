# Technical-debt report disposition — Nex 2.6.27

Input: `Nex_Technical_Debt_Merged_2.6.17_FA_v2_1.md` (owner-supplied, Persian):
21 open items from the 2.6.17 debt audit, 9 proposed steps (P01–P09) from a
UI-unification patch, and 3 new findings (N1–N3). The report was written
against **2.6.17** (`85fcb427`); every item below was rechecked against `main`
at 2.6.26 (`53044b4`) before anything was changed. The patch file itself was
not supplied, so its steps were judged from their description and redone
where they held up, rather than applied.

The rule from `docs/26-ui-consistency.md` holds: one UI family at a time.
2.6.27 takes the families that were small and confirmed; the rest are
recorded with what is left.

## Changed in 2.6.27

| Item | Finding on today's code | Change |
| --- | --- | --- |
| **N1** Markdown links in exports | **Confirmed.** `_markdownFor` wrote `../media/<basename>` before the exporter decided the entry name, so of two photos with the same file name the second note's Markdown pointed at the first photo. | Entry names are decided first and the Markdown links to the real entry (`export_markdown_media_test.dart`, shown failing on the old code: the second note read `first-photo`). Import was already right: it looks for the id-prefixed name first. |
| **A9** Unused translations | 85 keys (of 1,735) were referenced by no code. One, `spanMonths`, is used by the hand-written `l10n/relative_span.dart` and stays. | 84 keys removed from both catalogues; localizations regenerated. Both catalogues still match key for key (1,651). |
| **P03** Disabled field outline | **Confirmed, with a sharper cause than the report gave.** 33 fields passed Material's `OutlineInputBorder()` to get an outline; the theme had no `border` or `disabledBorder`, so a disabled field drew a 4 px grey corner beside 12 px ones. | The theme draws resting, disabled, focus and error outlines in all five renderers; the 33 overrides are gone; a ratchet keeps the default outline at 0 (`input_outline_test.dart` in `packages/ui`). |
| **P07** Words cap dialog | **Confirmed:** the last stock `SimpleDialog` in the app. | `NexAlertDialog` with full-height rows and the current value ticked; a test for both caps in both languages. A ratchet now keeps stock `SimpleDialog`/`AlertDialog` at 0. |
| **P08** Expenses time picker | **Confirmed.** It built `TimePickerDialog` directly, which the picker ratchet did not count, so the "raw pickers at 0" row was not true. | `nexPickModuleTime`; the ratchet counts hand-built picker dialogs too. Expenses is still Soon; its code is kept working. |

## Reviewed and left as they are

| Item | Disposition |
| --- | --- |
| **N2** Sync: a rejected note stays pending | **Behaviour confirmed, and intended.** The server omits a note from `merged` only for a stale write (`sync-service.ts`), the client keeps it pending, and the pull in the same cycle reconciles it before the next push — the case the outbox exists for (2.6.17 review, C7/E1). Marking it `conflict` or dropping it without a cause would lose an edit. Sync is still not offered to users. Revisit only with a reproduced permanent rejection. |
| **N3** Tool registry beside the assistant's actions | **Confirmed unused in production:** `NexToolRegistry`, `GatedToolExecutor`, `ToolDefinition`, `ToolCall` (~266 lines) are used only by their own test, and the `ai.entitlement` preference is never read. But this is the scaffolding ADR-029 and ADR-030 decided to build ahead of the paid assistant tier. Removing it reverses an accepted decision, so it is the owner's call; the code is small and costs nothing at runtime. |
| **A10** Notifications 23 | Done in 2.6.26. |
| **P01** One search field | **Done in 2.6.27, as its own family.** `NexSearchField` in `packages/ui` (search icon; clear that resets the list at once; direction from what is typed or fixed; `private`; `ground: surface`) and all 13 search boxes moved to it — Settings, Modules, What's new, vault, AI model list, Words, tags, translation languages, recurring attachment search, and the Soon modules' Expenses, Loans, Parking and Warranty. Before, five had a clear button with three different tooltips and the rest none. Ratchet at 0; the timeline pill is the exception. |
| **P02** Three field decorations | Belongs with P01 in the text-entry family. About 10 hand-made outlines remain (`settings_search`, `chat_composer`, vault, memory, onboarding). |
| **P04** One text field for Medicine, Parking, Warranty | All three modules are Soon. Kept for when they are reviewed for release, so the move can be checked on a device with them. |
| **P05** Shared `MenuAnchor` style | Only one `MenuAnchor` is left in the app; the menu family is done (`menu_rule_test`). Nothing to share. |
| **P06** Chat sheet handle and scrim | The chat sheet already follows the shared sheet's scrim rule; its handle is its own by design (the sheet resizes from it). No confirmed defect. |
| **P09** Ratchet tests | Done for what changed: dialogs, pickers and default outlines. |
| **B0–B5** Large files | Unchanged judgement from 2.6.17: a metric, not a defect. 2.6.26 did split along a real seam where it mattered (`NexRouteProbe` out of the timeline). |
| **C1, C4, C5, C6, C7** Similar code | Unchanged from 2.6.17: the similarities checked there hide different contracts. C5's confirmed instances are P07/P08 above. |
| **D3, D4, D6, D7, D8** Conventions | Unchanged from 2.6.17. D6 (language checks in many places) moves with P01 for search fields. |
| **E6, E7** CI | Unchanged: paused platforms stay paused; version and changelog equality checks are the guard, not the debt. |

## From this review itself

- **Workflow list on GitHub.** The Actions sidebar lists about twenty
  workflows; only five exist (`ci`, `release`, `stress`, `ai-testbuild`,
  `habits-review`) plus Dependabot. The rest are one-off workflows whose
  files were deleted but whose runs remain. They run nothing; they leave the
  list once their runs are deleted in the GitHub UI.
- **Route dependencies in callbacks.** 2.6.26 fixed the one that rebuilt the
  timeline. `NexTextField` and `DismissOnOverscroll` still call
  `ModalRoute.of` from callbacks, which makes each field rebuild when a route
  covers it. Small, and worth folding into the text-entry family pass.

## Validation

`packages/data`, `packages/ui`, `packages/core` and `apps/client`: analysis
clean and full suites passed; the counts are in the pull request.
