# Editor 2.9.5 — what to check on a device

The host tests cover the document model, the IME delta path, key-driven
deletion, selection mapping and undo. They cannot cover the things that only a
real keyboard, a real finger and a real GPU do. This is the list for a person
with a phone and a Windows machine. Anything that fails, note the platform, the
keyboard app and the note (a mixed one), and whether it reproduces from a clean
open.

Use one note for all of it:

```
سلام دنیا
Hello world
۱۲۳ ۴۵۶
نکس Nex را باز کن
```

## Forms and creation

- Write and paste the example in a new note and in a multiline module field.
  Tap between the Persian and English paragraphs and check that neither moves.
- In Prompt Studio, Family Fund and Habits, switch from a name to a multiline
  field and back with the keyboard open. Scroll the form after focusing the
  text. A wrapped field should grow until the limit and then scroll inside.
- In the capture sheet, switch between Note, Checklist, Link and Code. Verify
  the text, caret and keyboard survive. In Code, verify highlighting,
  indentation and paired brackets. With Enter-to-send enabled, verify Enter
  submits a note and Shift+Enter adds a paragraph.
- In the private vault, verify copy remains subject to its sensitive clipboard
  handling and the keyboard's personalised learning stays disabled.

## Android

1. **Open.** Open a long note (100+ lines, half of each script). It should
   appear within about a second and scroll smoothly.
2. **Layout at rest.** Every line sits on its own side: Persian right, English
   left, the digits line on the side of the line above it. Nothing is centred
   or clipped.
3. **Caret walking.** Tap the end of the Persian line, then the start of the
   English one, then back. The lines must not move, flip or re-align at any
   point — this is the bug the release exists for.
4. **Typing.** Type Persian into the Persian line and English into the English
   line. Text appears at the caret, in order, with no letters jumping to the
   other end.
5. **Composing.** With a keyboard that composes (Gboard with Persian), type a
   word without accepting a suggestion: the composing underline follows the
   word, and accepting it inserts the composed word in place.
6. **Enter.** At the end of a line, Enter makes a new line that takes its own
   direction as soon as a letter is typed. At the start of a line, Enter makes
   an empty line above.
7. **Backspace.** At the start of a line, Backspace joins it to the line above
   and the caret lands at the join. Repeated Backspace deletes across the join.
8. **Selection.** Long-press a word: handles appear on the word. Drag one
   handle up through several lines — the selection grows reversed (anchor
   stays at the bottom) and the editor does not scroll-jump or re-align.
9. **Handles and magnifier.** Drag a handle slowly: the magnifier shows the
   character under it, and the highlight follows the finger without lag.
10. **Formatting.** Select part of a line, open the toolbar's formatting menu,
    pick Bold. The marks apply to what was selected, the caret stays where it
    was, and the keyboard stays open.
11. **Copy, cut, paste.** Copy a mixed selection and paste it at the end: the
    text arrives unchanged and each pasted line takes its own direction.
12. **Undo.** Type a word, press undo (or Ctrl+Z with a hardware keyboard). The
    word goes, the caret returns to where it was. Redo brings it back.
13. **Rotation and resize.** Rotate the phone and open the full-screen editor:
    text, caret and selection survive, and the keyboard does not close.
14. **Keyboard switching.** Move from the note editor to another field and
    back: the keyboard must not close and reopen.
15. **AI rewrite.** Start a rewrite; while it runs, type on a hardware keyboard
    (or an on-screen one if it is still up). Nothing may change the note while
    the spinner is showing.

## Windows

1. Open the same note. Check 2–3 above (layout and caret walking).
2. Type in both scripts with the Windows Persian layout.
3. Enter, Backspace at a line start, Home/End, Ctrl+A, Shift+arrows (both
   directions), Ctrl+C/V/X, Ctrl+Z / Ctrl+Shift+Z.
4. Click at a position in a Persian line: the caret must land where the pointer
   is, and the formatting menu must format that selection.
5. Resize the window while typing: no jump, no lost caret.
6. Switch to another app and back: focus returns to the note and typing
   continues at the caret.

## If something is wrong

Record: platform and version, keyboard app and layout, whether the note was
opened or pasted, the exact keystrokes, and a screenshot of the line before and
after. For a direction bug, say which line changed side and where the caret
was — that is what tells a layout bug from a mapping bug.
