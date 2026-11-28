# Nex 2.9.5 — the editor lays out every paragraph at once

This is the developer record for the second reassessment of the editor's
direction handling. It reverses 2.9.4's field, keeps its keyboard, and answers
why neither a stock `TextField` nor AppFlowy Editor could deliver the rule the
owner asked for: **each paragraph in its own direction, on its own side, at the
same time, while editing.**

## 1. What was wrong, in the engine

Flutter's text stack builds one `ui.Paragraph` for a whole field, and a
paragraph has exactly one base direction. Everything 1.91–2.9.4 did was an
attempt to live with that:

| Release | Mechanism | What it could not do |
| --- | --- | --- |
| 1.91–2.9.3 | Android `EditText` in a platform view | keyboard closed on every native↔Flutter focus handoff |
| 2.9.4 | one `TextField`, laid out around the caret's paragraph | every other paragraph turned with the caret; selection handles relaid out under the finger; text jumped |

The 2.9.4 record called this an "honest limit". It was the reported bug: the
active paragraph's direction applied to the whole note, and moving the caret
or dragging a handle changed the layout of everything else.

Two consequences follow from the one-paragraph model, and no amount of care in
`NexAutoDirection` can remove them:

- neutral characters (`.` `!` `؟`) at the end of a paragraph are resolved
  against the **field's** base direction, so an English line in a Persian note
  puts its full stop on the wrong end;
- `TextAlign.start` resolves against the same single direction, so every line
  is aligned to the same side.

## 2. What the fix must be

One text component per paragraph — each its own `ui.Paragraph`, its own base
direction, its own alignment — over **one input connection for the document**.
One connection is not an optimisation; it is what makes Backspace at the start
of a paragraph join it to the one above, and Enter split it, instead of being
swallowed at a field's offset zero. That was the finding that ruled out "one
TextField per direction run" in 2.9.4, and it still rules it out.

## 3. The libraries, checked against their own source

**AppFlowy Editor 6.2.0** has the right model: per-node
`blockComponentTextDirection` (`ltr`/`rtl`/`auto`), per-node alignment, and a
single `TextInput.attach` with a document-level delta client. It cannot be
installed in Nex: it depends on `device_info_plus ^11`, which needs `win32 ^5`,
while the app's `share_plus 13.3` needs `win32 ^6`. Resolving that means
downgrading sharing or force-overriding `win32` across three plugins — a
broken Windows build in exchange for an editor. Rejected. (Its licence is dual
AGPL-3.0 / MPL-2.0; MPL would have been compatible with Nex's MIT, so the
decision is dependency compatibility, not licensing.)

**Super Editor 0.3.0-dev.52** is MIT, resolves against the app's dependency
set unchanged, and has exactly the required shape:

- `ParagraphComponentBuilder.createViewModel` gives every paragraph a
  `textDirection` resolved from **that paragraph's own text**, and an alignment
  derived from it (`paragraph.dart`);
- one document-level IME (`supereditor_ime_interactor.dart`,
  `document_ime_communication.dart`) with cross-node editing;
- the mobile handles, magnifier, toolbars, undo/redo and platform shortcuts.

Its own direction rule is not good enough: `getParagraphDirection` looks at the
paragraph's **first character** and answers left-to-right for anything outside
a right-to-left block, so `Nex را باز کن` would be laid out left to right and
`۱۲۳` would be laid out right to left even though digits carry no direction.
`nex_paragraph_editor.dart` replaces that rule with Nex's own: the paragraph's
first **strong** character, then the nearest paragraph before it that has one,
then the nearest after, then the surface's direction — UAX #9 P2/P3 with the
stickiness a new line needs. Alignment follows that direction.

## 4. What changed

| Area | Change |
| --- | --- |
| `pubspec.yaml` | `super_editor: 0.3.0-dev.52`, pinned, MIT. Pub packages' licences already reach the in-app licence page through Flutter's NOTICES. |
| `nex_paragraph_editor.dart` | New: builds one paragraph node per line from the controller's string, maps selection both ways, rebuilds on external writes, owns the direction/alignment override. |
| `note_editor_sheet.dart` | The text field is the new editor. Formatting commands moved from the field's selection menu to a header menu, where they work on every platform with the keyboard up. |
| Data | Nothing. The note is the same plain string: paragraphs joined by `\n`, no marks or isolates written into it. |

## 5. Validation

Host tests (`apps/client/test/`): `nex_paragraph_editor_test.dart` holds one
paragraph per line, per-paragraph direction for Persian/English/digits/mixed,
per-paragraph alignment, absolute caret offsets, external writes, and the
engine's direction rule; `text_selection_test.dart` holds a multi-paragraph
selection, a caret move that changes nothing else, and directions that survive
a selection; `note_editor_sheet_test.dart` and `note_editor_resize_test.dart`
were ported to the new editor and pass in both languages, both text scales and
reduced motion.

Not validated, and named here rather than implied: no device was available, so
the Android soft-keyboard behaviours (Backspace at a paragraph start, Enter
splitting, composing text, the magnifier and the drag handles) are covered by
the engine's own implementation and by its upstream test suite, not by a
physical run; and the formatting menu's new position was not seen on a device.

## 6. Audit, 2.9.5

### What was wrong with the first implementation

Four things, found by reading it again and by driving it through the paths a
person drives:

1. **A reversed selection was flattened.** `_build` placed the document's
   caret from `selection.start` and `selection.end`, which are always ordered,
   so a drag from the bottom of a paragraph upwards reached the document as a
   forward selection. The controller now keeps `baseOffset`/`extentOffset`, and
   the comparison that decides whether to write the controller compares those
   fields, not their ends.
2. **The controller never followed a tap or a drag.** The state listened to the
   composer itself, but `DocumentComposer` publishes selection changes on
   `selectionNotifier`; its own listeners hear about composing regions and
   interaction mode. The editor's caret moved and the controller's stayed put,
   so the formatting menu — which reads the controller — formatted the old
   position. Found by the input tests, not by any earlier suite: every earlier
   test set the selection through the controller, which is the path that
   already worked.
3. **Undo and redo were invisible to the cache.** `Editor.undo` rolls the
   editables back and notifies with an **empty** change log, so the incremental
   path concluded nothing had changed. An empty log now rebuilds the paragraph
   index, because an empty log means "all of it, unknown".
4. **`readOnly` was `IgnorePointer`.** An ignored pointer still holds the
   platform input connection: a hardware keyboard could type into the document
   that the AI rewrite was about to replace. Read-only now renders the same
   document through `SuperReader`, which has no input connection at all.

### What a keystroke costs, and what the paragraph cache was worth

The note is mirrored the simple way: each document change joins the paragraphs,
writes the controller and refreshes the direction map. An earlier version of
this file also kept a per-paragraph cache, a start-offset table and a
binary-search caret mapping. Measured on 500, 2000 and 5000-line mixed notes,
with frames excluded so the numbers are document work and not layout:

| lines | with cache (type / verify) | without cache |
| --- | --- | --- |
| 500 | 32.9 ms | 26.0 ms |
| 2000 | 151.0 ms | 113.9 ms |
| 5000 | 324.1 ms | 275.2 ms |

The cache was **not faster** at any size — within noise at best, consistently a
little slower because it allocated four lists and a map per keystroke. It was
removed. What dominates a keystroke is upstream: Super Editor serialises the
whole document for the IME and re-sends it on every delta. The direction map
stays, because it is one pass per text change and it keeps a relayout from
walking the document per paragraph.

### Against 2.9.4

The same notes, in `NexTextField` — the field 2.9.4 shipped — typing arriving as
a whole value update the way Flutter's test IME sends one, one frame per
keystroke on both sides:

| lines | 2.9.4 open | new open | 2.9.4 per keystroke | new per keystroke | 2.9.4 per caret move | new per caret move |
| --- | --- | --- | --- | --- | --- | --- |
| 500 | 647 ms | 1268 ms | 68.2 ms | 25.0 ms | 14.3 ms | 4.4 ms |
| 2000 | 561 ms | 2236 ms | 376.0 ms | 87.6 ms | 76.4 ms | 13.2 ms |
| 5000 | 2051 ms | 4143 ms | 1773.2 ms | 218.5 ms | 302.4 ms | 40.8 ms |

So: the document engine costs about twice as much to **open** a long note, and
answers typing 2.7× faster at 500 lines, 4.3× at 2000 and 8.1× at 5000, with
caret moves 3–7× faster. The field's cost grows faster than linearly with the
note because it lays the whole note out around the caret's paragraph on every
change; the document engine lays out the paragraphs the change touched. Both
numbers are from a debug test host, not a device, so treat the **ratios** as the
finding and the absolute times as indicative.

### Remaining prose fields: what unification needs

Only the note editor uses the document engine so far. The capture composer —
the place a note is first written — and the module note fields still use
`NexTextField`, and they still have 2.9.4's behaviour: the paragraph being
edited and the rest of the field are laid out as one paragraph, so a mixed note
turns as the caret moves.

Moving them is not a one-line swap. Three things are missing from
`NexParagraphEditor` before it can stand in for a `NexTextField`:

1. **Field chrome.** `decoration` (hint, helper, error, borders) and the
   min/max line box a `TextField` grows in. The engine currently fills the space
   it is given and draws no hint.
2. **The formatting menu.** The capture composer's note field offers
   bold/italic/mono/strike/quote/link through the platform selection menu.
   Super Editor draws its own selection toolbar, so that menu has to be rebuilt
   on the document engine (or moved to a visible toolbar), or the composer loses
   a feature when it switches.
3. **One field for every capture kind.** The composer deliberately keeps one
   field instance across Note, Checklist, Link and Code, because swapping the
   editor when the kind changes takes the keyboard with it. Code needs a
   monospaced, left-to-right document with its bracket/indent formatter; the
   document engine can be monospaced and forced left-to-right, but the input
   formatter has no equivalent there yet.

Until those three exist, converting the composer would trade the direction bug
for a lost formatting menu and a keyboard that blinks on Note↔Code; converting
the module fields would trade it for missing hints and wrong heights. The
`NexTextField` path stays for code (`snippet_editor_sheet.dart`, capture Code,
security toolbox) and for the private vault, as asked.

### What the tests now drive

`test/nex_paragraph_editor_input_test.dart` (7 tests): typing through the IME
against the value the engine published to it; the IME's newline splitting a
paragraph, with each line taking its own direction; Backspace joining across a
paragraph boundary; a selection anchored below and extended above arriving in
the controller reversed; the caret walking the whole note without any
paragraph's direction or alignment changing; undo and redo restoring text, caret
and string; read-only having no input connection.

Character input reaches Super Editor through the IME on every target
(`TextInputSource.ime` is its default), so a "hardware typing" test would be
testing a path that does not exist; the keys that are keys — Backspace, Enter,
undo — are tested as key events.

### Not validated

No device or emulator was available. The soft keyboard on Android (composing
text, the GBoard newline behaviours Super Editor special-cases, the magnifier and
drag handles), Windows IME behaviour, and touch scrolling inside the editor were
not exercised. `docs/development/nex-2.9.5-editor-device-checklist.md` is the
run-through for a person with a device.

A full `flutter test` run over the app's 545 test files passes. The one failure
it used to report — `modules/expenses` "nothing is offered before its day",
which created a template due on the 28th and expected it to be ahead — was a
date-dependent test, not an editor bug: it failed on the 28th of any month. It
now pins the screen's clock through `ExpensesScreen(now:)` instead of reading
the wall clock, so it answers the same on every day.
