# Changelog

What ships in the update sheet, one release at a time — written for the
person tapping "Check for update", not for someone reading `git log`. No PR
titles, no commit hashes, no internal refactors: only what changes for
someone using the app.

## How this file is used

The section named after the tag being released — `## vX.Y.Z` — is exactly
what `release.yml` publishes as the GitHub Release body, and exactly what
the in-app update sheet then shows. That is the whole mechanism: no separate
changelog service, no template rendered at request time.

It is looked up *by name*, not by position, which is what lets the fresh
`## Unreleased` below sit above the newest release without being mistaken
for it. Position was tried and is wrong at both ends: this prose section is
itself a `## ` heading, so "the first `## ` heading" published these
instructions as the release notes; and "the first release-shaped heading"
would match the empty `## Unreleased` on every release after the first.

Working convention:

- Add each user-facing change as a short bullet under **Unreleased**, in the
  same pull request that makes the change. If it does not change anything a
  user would notice, it does not belong here — that is what the commit
  history is for.
- When cutting a release, rename `## Unreleased` to `## vX.Y.Z` (matching
  the tag about to be pushed) and start a fresh `## Unreleased` above it for
  whatever comes next.
- `release.yml` refuses to publish a tag that has no section of its own, so
  forgetting to rename `## Unreleased` fails the release instead of shipping
  a version with someone else's notes — or none at all.

## Unreleased

- Timeline cards are back to their original height. The two-line preview
  stayed; the time a note was last touched moved next to its icon, which
  is what was taking the room.
- The greeting and the line under it are centred, and both now follow the
  language they are written in — a Persian line no longer came out with
  its full stop at the wrong end.
- The daily summary reads right-to-left when it is written in Persian.
- The logo in the corner lost the grey tile behind it; it was not a
  button, so it should not have looked like one.

## v0.9.2

- Timeline cards show two lines of a note instead of one.
- Fixed a brand-new install already listing a backup — of an empty library.
- Fixed the last update refusing to install over the previous version. Both
  causes are gone: releases stopped shipping the per-architecture APKs at
  all, and the version numbering let an older build outrank a newer one.
- Messages arrive from the top of the screen now, as a rounded banner with a
  small vibration, instead of a bar at the bottom. Tap it or flick it up to
  send it away early.
- Any note can be given a title now, from its detail sheet. A named note
  shows its name in the list, and is still searchable by what is inside it.
- Added checklists. Write one item per line, and tick them off later — a
  checklist exports as a real markdown checklist too.
- Added link captures. Paste a link and Nex reads the page's own title and
  description, and summarises it if you have an AI provider set up.
- A first launch now opens with a short introduction to what Nex is, ending
  with your name, theme, language, and the language Nex writes in. It appears
  once, and never for an install that already has notes in it.
- The top of the home screen is a real header now: a short line written for
  you, your greeting above it, and the daily summary in a card under both.
  Tap the line for a different one.
- The daily summary card keeps its own refresh and collapse buttons, so it
  folds away and comes back from the same place instead of from the app bar.
- Settings is one line per setting now, with what it is set to beside it.
  Every picker still opens — from the row that names it — instead of all of
  them sitting open at once.
- Your name sits at the top of Settings as a profile card rather than in a
  section of its own halfway down.
- Added a setting for which language Nex writes in — follow your notes,
  English, or Persian — separate from the language of the app itself.

## v0.9.1

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
- Tag colours now show as small dots on the note's own icon instead of a
  column beside it, and that icon is smaller and rounder.
- The timeline's dark background is a touch warmer.
- With an AI provider configured, the timeline now opens with a short,
  friendly recap of recent notes, generated once a day; it collapses on the
  first scroll and reopens from a small chip beside the greeting.
