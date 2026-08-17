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

- The assistant can look through your whole library, not just the last
  handful of notes. When it needs one it does not have, it searches for it
  and answers from what it finds.
- It can do more than write and delete now: combine several notes into one,
  turn a note into a checklist, tick an item off, and change your theme,
  language or the language it writes in. Those four settings are the only
  ones it can touch — never your API key, your sync server, or anything that
  would be hard to undo.
- When a request needs more than one change, it asks for all of them at once
  and shows you every one before anything happens. It still never acts on
  its own.
- Search by meaning now actually works on the notes you already had. Nex
  could always find a note by what it means rather than the words in it —
  but only for notes captured after you set up an AI provider. Everything
  written before that was never indexed, and never would be, so the feature
  quietly found nothing. The backlog is worked through now.
- The search box takes `tag:` and `type:` — `tag:work type:link cooler`.
  Quotes hold a phrase or a tag with a space together: `tag:"to read"`.
  These combine with the filter chips rather than replacing them. A search
  you want back can be kept — it appears as a chip on the empty search
  screen, which is the one moment it is useful.
- A note's detail sheet has an Ask button: the assistant, about that one
  note. It reads the note's transcript or the text found in a photo too, so
  you can ask about a recording or a picture, not only about typed notes.
- Backups now contain your photos, voice recordings and attached files. They
  never did: a backup was the database and nothing else, so restoring on a
  new phone brought back every note with every picture missing — and said
  nothing, because the notes were all there. Backups written from now on are
  `.nexbak` files, which are ordinary zips: your notes can be pulled out of
  one with any unzip tool, without this app. Older `.sqlite` backups still
  restore, and restoring one leaves the files on your device alone.
- The assistant remembers your conversations. The history button in its
  header lists them, reopens one where it left off, and deletes any or all
  of them. Nothing is sent anywhere — they are kept on this device.
- The assistant has settings of its own, under Settings › Assistant:
  how creative it is, how long its answers may be, how many recent notes it
  can see, and whether it stays inside your notes or answers anything.
- It can now write to your notes: create one, rewrite one, delete one, or
  change its tags. It never does any of that on its own — it asks, you see
  exactly what it would do, and it happens only when you press the button.
- The assistant's send button no longer sits under the phone's own
  navigation buttons.
- Your own messages in the chat are readable again — the text and the bubble
  behind it were being coloured independently.
- The light around the screen while you hold the capture button is softer and
  moves as it builds, and it fades as the chat opens instead of blinking out.
- The Chat row in Settings used to open a chat that answered "unavailable" to
  everything on every published build. It opens the assistant's settings now,
  and there is one chat in the app: hold the capture button.

## v0.9.3

- Timeline cards are back to their original height. The two-line preview
  stayed; the time a note was last touched moved next to its icon, which
  is what was taking the room.
- The greeting and the line under it are centred, and both now follow the
  language they are written in — a Persian line no longer came out with
  its full stop at the wrong end.
- The daily summary reads right-to-left when it is written in Persian.
- The logo in the corner lost the grey tile behind it; it was not a
  button, so it should not have looked like one.
- Naming a note by hand is gone again. Nex is not a filing app, and a
  capture is meant to be finished the moment it exists. Links still show
  the page's own name, which is what that was ever really for.
- The daily summary card and the search field are the same roundness now.
- Pull-to-refresh is gone from the timeline; it had nothing left to do.
  Coming back to the app re-reads your notes instead, which covers the
  one case the pull was there for.
- The generated line under the greeting is set at the daily summary's size
  now, instead of at headline size. It is a flourish, not a title.
- The capture box's placeholder sits at the right edge in Persian, where it
  belongs, instead of the left.
- The AI service screen stopped mirroring itself in Persian. Keys, endpoints,
  model names and provider names are Latin text and now read left to right;
  the Persian explanations around them are unchanged.
- The daily summary and the line above it are written to a better brief:
  warmer, drier, and about the actual thing you wrote rather than the
  category it falls into.
- A reply that is not a sentence — several scripts deep, words repeating,
  the shape small free models fail into — is now discarded rather than shown
  as the app's own voice. You get the previous line and a tap to try again.
- Fixed replies arriving as mojibake from providers that send UTF-8 without
  saying so. This affected Persian output specifically.
- Hold the capture button to ask the assistant something. The screen lights
  up around its edge while you hold, and the chat opens as a small panel at
  the bottom that you can drag up to full screen. It uses the AI provider
  you set up in Settings, and answers in the language you chose there; with
  no provider configured, the hold does nothing.

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
