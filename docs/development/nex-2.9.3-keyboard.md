# Nex 2.9.3 — the keyboard, root-caused

This is the developer record for 2.9.3's keyboard work. It follows
[`nex-2.9.2-performance.md`](nex-2.9.2-performance.md), and it exists because
2.9.2's device verification failed where it mattered: the physical test
confirmed the performance work — the delete, the switch, the brief — but the
keyboard still closed on field-to-field transitions. The owner's result,
narrowed by module:

- **still closing:** Prompt Studio (the entry editor's title→body, the
  details' category→notes, and the workbench's fill fields), Gold (the save
  sheet's note field);
- **clean:** Price Lens, Lent & Borrowed.

The method and its limits are the same as the two records before it: a Linux
container, Flutter 3.47.9, no physical phone. What follows is code reading —
including the framework's own `PlatformViewLink` — plus widget tests that
drive the real protocol, run on the host.

## 1. What the four modules actually differ in

The input implementations do not differ. All four modules use the same
`NexTextField`, the same `NexImeHandoff`, the same dismisser; none has a
local keyboard rule. What differs is **which transitions the typing path
makes**:

| Module | Native editors | The path a person types |
| --- | --- | --- |
| Prompt Studio (editor) | title, body (+ category, notes in details) | **native → native**, repeatedly |
| Prompt Studio (workbench) | one per template slot, up to 24 | **native → native**, repeatedly |
| Gold (save sheet) | notes, between the Flutter date field and Save | **Flutter → native → onward** |
| Price Lens | product, shop — behind "More details" | label → price → quantity: Flutter → Flutter; the native pair sits on an optional branch |
| Lent & Borrowed | note, the last field of the form | amounts → dates: Flutter → Flutter, ending in the note with nothing after it |

Prompt Studio is the only module whose forms chain native editors, and Gold's
save sheet is the one place a person moves into a native editor mid-form and
carries on. Price Lens's native pair is reached only on the details branch,
and Lent & Borrowed's note is terminal — nothing follows it to hand to, so
whatever the handoff does between fields is never exercised. The failing
modules are exactly the ones whose typing paths perform the transition the
handoff's race lives in. That pointed away from the modules and at the
handoff itself.

## 2. Root cause: a native focus-loss event was a dismissal trigger

Two facts, one from Android and one from the framework, make the 2.9.2
design wrong at its base.

**Android dispatches the loss around every handoff.** When focus moves from
editor A to editor B in one window, A's `onFocusChange(false)` fires next to
B's `onFocusChange(true)` — the loss is not an ending, it is the first half
of the handoff. The window's own `InputMethodManager` then does the right
thing without any help: it switches the served view and keeps the keyboard.

**The framework sends a second, stale loss.** `_PlatformViewLinkState`
(Flutter's own code, read from the 3.47.9 SDK) calls
`_controller?.clearFocus()` whenever the link's node loses Flutter focus and
re-informs `TextInput.setPlatformViewClient` on every focus change. So each
native→anything transition delivers *another* `onFocusChange(false)` for the
old view, after the Flutter tree has already moved on — a loss report for an
editor whose successor has the keyboard.

`NexImeHandoff.editorLostFocus` answered this event with a deferred hide: it
armed a 150 ms window-level IME dismissal (`_unfocusEditor` →
`NexEditText.unfocus`, which hides, plus `nexHideKeyboard()`), skipped only
if another editor had *reported* by then. That made the dismissal a race
against a report that is always in flight, and the loss was guaranteed to
arrive — twice — on exactly the transitions Prompt Studio and Gold perform:

- a successor whose `onFocusChange(true)` is delivered late — a slow editor
  or a third-party IME restarting its input connection when the served view
  switches — lost the keyboard it already owned: the hide fired, the window
  keyboard closed, the successor reopened it;
- every later, stale loss cancelled any pending hide and **re-armed a fresh
  one**, so a late report could start a new countdown over a keyboard
  another field was using.

Both halves are the close-and-reopen the handoff exists to prevent, one
settle window later. 2.9.1 deferred the hide; 2.9.2 made the reports
order-independent. Both kept the event 2.9.3 removes: the trigger itself.

A third fact closed the design. The framework's focus sweep
(`applyFocusChangesIfNeeded`) notifies the **new** path's nodes before the
**old** path's (`_dirtyNodes` receives `nextPath.difference(previousPath)`
before `previousPath.difference(nextPath)`). So a successor-side "cancel"
can never win against the old field's arm inside one sweep — the arm is
always notified last. The decision therefore has to be made where the arm
is, not where the claim is.

## 3. Corrections

**A native loss is bookkeeping, and only bookkeeping.**
`editorLostFocus(editor)` removes the editor from the registry and does
nothing else — it takes no hide, cancels no pending hide, schedules nothing.
A native focus-loss event never dismisses the IME. The cases the removed
trigger was nominally for are owned elsewhere: the window itself decides
what a cleared editor means (keeps the keyboard for the next editor in the
window, hides it when nothing follows), and every dismissal that expresses
an intent has its own path — `lose()` when the Dart side gives a field's
focus up, `nexDismissKeyboard` when a route leaves, the editor's own
`dispose()`. A loss does not cancel a hide the Dart side armed, either: the
person asked for the keyboard to go, and the event that follows their ask is
not news.

**The successor's claim is the focus move, not the report.** The handoff now
keeps the focus nodes of the mounted native fields
(`editorNodeAttached`/`editorNodeDetached`), and `lose()` asks — at arm time
and again when the timer fires — whether a text editor holds the primary
focus: an `EditableText` (Flutter's) **or a native field's node**. The
engine reports an embedded editor's focus to the platform view's own node
inside the field's, and Dart focuses the field's node to hand its editor the
keyboard, so whichever way the successor was reached, the tree sees it the
moment focus moves — no report has to win a race against the settle window.
This is the arm-side decision the sweep order demands.

**A field's own platform-view node claiming focus is a claim.**
`_NativeFieldState._onFocus` now recognizes the middle case it used to
ignore: the platform view's node, inside the field's, has gained primary
focus (the engine reporting that Android's editor took the keyboard — how a
person's tap on the editor itself arrives). That cancels this field's and
any other field's pending hide, and sends no command: the editor already
took focus on its own.

The 150 ms `delay` is unchanged — it is no longer a race window between two
reports but only the debounce between a person's intent (unfocus) and the
hide, re-checked against the live focus tree when it fires. No timeout was
increased; the race was removed.

## What was deliberately left alone

- `nexDismissKeyboard` and `nexHideKeyboard` (route teardown, save paths) —
  real intents, unchanged.
- The Kotlin side: `NexEditText`'s `unfocus` (clearFocus + window hide),
  `dispose` (hides from a focused editor), and the `focus` re-show —
  unchanged.
- `NexKeyboardDismisser`, `NexGuardedField`, `NexFocusReveal` — untouched;
  no module's own code changed.

## Tests run for this change

All on Flutter 3.47.9, `--concurrency=1`, each command under an enforced
timeout (a command that times out counts as failed):

- `flutter analyze --fatal-infos` — clean.
- `flutter test test/nex_text_field_test.dart
  test/keyboard_dismisser_test.dart` — **50 passing** (46 before, 4 new):
  - *the next editor's claim does not wait for its own report* — the device
    failure end to end: the successor's platform-view node takes Flutter
    focus, the settle window passes with the successor's report still in
    flight, then the reports land late (the gain, then the old field's stale
    loss): no `unfocus`, no window hide, at any point;
  - *a native loss alone dismisses nothing* — a loss report with no
    successor and no Dart-side unfocus arms nothing, past the whole settle
    window (this one fails on the 2.9.2 code, which armed a hide on the
    event itself);
  - *a native loss does not cancel a hide the Dart side armed* — the
    dismisser's unfocus, then the editor's report of what followed it: the
    hide still fires;
  - *a native loss is bookkeeping* — the handoff's own registry semantics.
- `flutter test test/modules/prompt_studio test/modules/gold
  test/modules/price_lens test/modules/lent_borrowed` — **542 passing**
  (the four modules of the report, untouched and green).
- `flutter test test/focus_reveal_test.dart test/search_field_header_test.dart
  test/input_focus_outline_test.dart test/text_field_rule_test.dart
  test/capture_native_paste_focus_test.dart test/capture_kind_switch_test.dart
  test/note_editor_native_resize_test.dart test/os_capture_bridge_test.dart
  test/version_test.dart test/whats_new_test.dart` — **90 passing**.
- `flutter test test/note_editor_sheet_test.dart
  test/capture_typing_rebuild_test.dart test/capture_paste_link_test.dart
  test/note_formatting_test.dart` — **37 passing**.

## Device verification that remains

1. **The owner's four flows, the reported phone**: Prompt Studio entry
   (title → body → details: category → notes), the workbench's fill fields
   in sequence, Gold's save sheet (date → notes → back), and the clean pair
   (Price Lens's product → shop, Lent & Borrowed's dates → note) — no
   close/reopen on any transition, on the stock keyboard and the
   third-party IME the failures were seen on.
2. **The other side of the change**: with a native field focused, a tap on
   empty space, a non-field control, and a route exit must still close the
   keyboard — the Dart-side paths are all that dismiss now.
3. **A third-party IME that restarts its connection late** on the successor
   editor: the successor's claim is now the focus move, so the report's
   timing should no longer matter; confirm none is visible.
