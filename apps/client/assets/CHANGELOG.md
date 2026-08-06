# Changelog

What ships in the update sheet, one release at a time — written for the
person tapping "Check for update", not for someone reading `git log`. No PR
titles, no commit hashes, no internal refactors: only what changes for
someone using the app.

## How this file is used

The top section (the first `## ` heading, whatever it is titled) is exactly
what `release.yml` publishes as the GitHub Release body — and exactly what
the in-app update sheet then shows. That is the whole mechanism: no separate
changelog service, no template rendered at request time.

Working convention:

- Add each user-facing change as a short bullet under **Unreleased**, in the
  same pull request that makes the change. If it does not change anything a
  user would notice, it does not belong here — that is what the commit
  history is for.
- When cutting a release, rename `## Unreleased` to `## vX.Y.Z` (matching
  the tag about to be pushed) and start a fresh `## Unreleased` above it for
  whatever comes next.
- `release.yml` refuses to publish if the top section is still literally
  titled `Unreleased` — that heading has to be renamed first, every time.

## Unreleased

- Settings' swipe-action picker now looks like the rest of Settings, not a
  system pop-up menu.
- Android updates download a much smaller file — the app matches its own
  device architecture instead of always fetching the universal build.
- The Voice/Camera/Gallery/File icons on the capture sheet are icon-only now.
- A caption you write for a photo or voice note takes priority over the
  text Nex read out of it, for both display and the copy button.
- Delete moved into the same icon row as the note's other actions, in red.
- Added a Settings control to scale the app's text and UI size up or down.
- Enter now submits your first line of text by default instead of starting
  a new line — Shift+Enter still does, and it can be turned off in Settings.
- Added a way to send feedback straight from the About screen.
- The About screen's logo and the splash screen are a bit smaller.
- Tags you add without picking a colour get a colour of their own instead
  of staying grey.
- Every note now shows how long ago it was last touched — "5m", "2h", "3d".
- Fixed the capture button showing up while searching.
- Fixed tapping a search result sometimes closing search instead of opening
  the note.
- Fixed a tag not disappearing from the filter row after its last note was
  moved to Recently Deleted, until the trash was emptied.
- The icon next to each note is rounder, and lost its outline.
- Added an accent-colour picker in Settings — pick one colour, and the caret,
  focus rings, and every other accent-tinted control follow it.
- The update screen now shows what actually changed, as a real list, instead
  of one long paragraph.
- Toasts pop in instead of just fading.
- Feedback is now a compose-and-send sheet instead of a link to copy, with a
  confirmation when it lands and an automatic retry if you were offline.
- Rotating and freehand drawing/text are now part of the photo crop step.
- Search now also looks by meaning, not just matching words, when nothing
  else turns up.
- The update screen now shows the full changelog inline, past versions
  included, instead of only the newest release's notes.
- Fixed pasting a long block of text into a capture pushing the send button
  off the screen — the text box now scrolls instead of growing forever.
- Fixed the feedback compose box ending up hidden behind the keyboard.
- Toasts now settle into place with a visible pop instead of the effect
  barely registering.
- Fixed the changelog list not showing on a real install (it bundles its own
  copy now instead of an asset path that only worked under tests).
- The note detail action icons fade at the edge when there is more to
  scroll to, on phones too narrow to show them all at once.
