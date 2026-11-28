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
