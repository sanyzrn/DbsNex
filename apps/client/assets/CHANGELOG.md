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

- **Reminders arrive.** They never have. The alarm was set correctly and the
  app said so, but nothing in the build claimed the message Android sends when
  it goes off, so it went nowhere — which is why the phone's own notification
  settings for Nex listed no categories at all. Nex now also verifies with the
  system that an alarm was really kept, and says so when it was not, instead of
  confirming a reminder that will never come. Settings › Notifications has a
  test button that sends one immediately and one ten seconds later, so a phone
  that still refuses can be told apart from an app that never asked.
- Typing in the wrong direction is fixed everywhere it was still wrong — the
  checklist, tag names, your own name, the annotation box, feedback and tag
  search. Each of them now follows the script you are typing rather than the
  language the app is set to, so a Persian line in an English app stops
  reordering itself as you write it.
- Folding a date group no longer makes the groups below it flicker open.
- The reminder no longer squeezes a note's own words off its card: on a note
  with one, the countdown takes the timestamp's place rather than sitting
  beside it.
- The separators in a note's action row can be seen now. They were set two
  steps quieter than the quietest boundary colour, which came to the same thing
  as not being there.
- The Persian throughout the app speaks to you one way instead of two. It
  drifted between formal and informal from screen to screen; it is formal
  everywhere now, apart from the greeting, which is meant to sound like a
  person. Three descriptions that had gone stale were corrected as well —
  including one that claimed your provider key is stored unencrypted, which
  stopped being true when keys moved into the device's secure storage.
- The Gemma licence notice keeps its English wording, because those terms
  require that exact sentence, but it is laid out left-to-right in a Persian
  interface now and has a plain Persian line under it saying what it means.

## v0.9.8

- A reminder that has been set says when it is for. The card carries how long
  is left — "in 2 hours", "in 3 days", or "Overdue" — and opening the reminder
  shows the exact day and time above the choices that would replace it. It used
  to be a bell and nothing else, so the only thing you could do to a reminder
  you could not read was delete it.
- The swipe on a card starts from almost anywhere on it. It used to need the
  outer third of either edge — a strip that existed to protect the long press
  that lifted a card for reordering, and reordering is gone. Now it is 45% from
  each side, leaving a narrow band down the middle that starts nothing, so
  there is still somewhere to put a thumb and scroll.
- A swipe can do more than delete or tag. Pin, Remind, Share and Ask the
  assistant join the list — everything the note detail sheet could already do,
  one gesture closer. Settings shows each edge as a row saying what it does
  now, with the whole list behind it; two grids of preview cards was fine at
  two actions and a wall at six.
- The date headings line up with the notes under them, sit further from the
  rows around them, and fold with an animation instead of a jump cut. A run
  closing now shrinks away; one opening grows in.
- The timeline is quieter: more space between cards, and the shadow under each
  one is gone. The card's own fill carries the boundary now, and the dark
  theme's page colour was deepened to keep that boundary visible without it.
- A photo no longer goes straight into the cropper. It opens on the photo
  itself with two buttons — use it, or edit it first — because most photos need
  no edit and putting one in the way of every capture made it a toll. The
  editor's own controls moved to the bottom of the screen at a size a thumb can
  reach, instead of small icons in the top corner.
- A Markdown file opens in Nex instead of only being listed. Share a `.md` into
  the app and the note shows the document itself — headings, lists, quotes,
  tables and code — under the filename, laid out in the direction the file is
  written in rather than the direction the app is set to. Very large files are
  still named rather than rendered, and say why.
- The assistant's answers are formatted. It has always written lists and bold
  text; you were reading the asterisks. Your own messages are left exactly as
  you typed them.

## v0.9.7

- The timeline is grouped by date — Today, Yesterday, Last week, Last month,
  Older — and each heading folds. A folded group says how many notes are under
  it, and stays folded until you open it, including after you close the app.
- Notes can no longer be dragged into a hand-made order, and the order is
  always the dates. A heading that says "Yesterday" has to be telling the
  truth about every note beneath it, and a hand-placed note lands in whichever
  group it was dropped next to. A pinned note keeps its place at the top,
  under its own heading.
- Reminders arrive on time. They were scheduled as approximate alarms, which
  Android is free to defer for hours while the phone is idle — so a note due at
  nine could turn up at lunchtime, or not that day. Nex now asks for the same
  kind of alarm the clock app uses, and falls back to the old behaviour only if
  the phone refuses.
- Setting a reminder says how far off it is — "2 hours from now" — the way
  setting an alarm does, instead of only "reminder set". And if the phone
  refuses the alarm outright, it says that too, rather than confirming
  something that will not happen.
- The row of actions under a note is grouped now, with a hairline between
  groups, and the assistant's three — ask, translate, summarise — sit together
  in the accent colour. Asking about a note is the sparkle the rest of the app
  uses for AI, instead of a speech bubble that could have meant anything.
- Opening the assistant from a note says which note it is about. It always
  answered from that one note; there was just no way to tell.
- Importing from Google Keep brings the photos across. It only ever read the
  words: a note that was a picture with a line under it imported as the line,
  and a note that was only a picture imported as nothing at all. Both are notes
  now, with the photo. A picture the export did not actually carry is still
  counted as skipped rather than quietly dropped.
- The date and time pickers look like the phone's own again. Nex's text-size
  setting was being applied to them, and a dial laid out at fixed sizes does
  not survive that.
- A once-a-day notification, off until you turn it on in Settings under
  Notifications, at a time you pick. It opens with your name and carries the
  day's recap under it. What it can say is whatever Nex last knew: the
  notification arrives while the app is closed, so the line is written the last
  time you had it open rather than at the moment it appears.
- The assistant can read more of your notes. It stopped at fifty; a hundred and
  two hundred are now offered, and picking one of those says what it costs —
  every question gets slower, because the model reads all of them before it
  answers, and on the on-device model it is very noticeable.
- The home screen opens with one sentence instead of two. The greeting and the
  generated line were separate thoughts sitting on top of each other; the model
  now writes the greeting itself, your name follows it, and if there is no
  model the app's own wording takes its place.
- Typing a Persian sentence with an English word in it no longer scrambles as
  you type. The chat box took its direction from the interface language rather
  than from what was in it, so the words reordered around the wrong side and
  only settled once the message was sent. It now turns to whichever script you
  are writing in, and turns back.
- The mark in the top corner is drawn the same size as the icons opposite it.
  The image has transparent space built into it, so a box that matched them
  drew something visibly smaller.

## v0.9.6

- The assistant can run on your phone, with nothing sent anywhere. Settings ›
  On-device model downloads Gemma 4 E2B once — about 2.6 GB, over Wi-Fi, and it
  stays on the phone — and from then on the assistant answers with no internet
  and no provider key. Ask it something on a plane and it answers.
- The download has Pause, Resume and Stop, and leaving the screen does not
  touch it. Pause keeps everything that has arrived; Stop throws it away and
  says so before it does. It shows how much has come down against how much
  there is, in gigabytes rather than a percentage, because on a data plan that
  is the number that matters.
- It survives a dropped connection, resuming where it stopped rather than
  starting the 2.6 GB again, checks the file against a known fingerprint before
  using it, and tells you if your phone does not have room before it begins
  instead of after. You can delete the model later and get the space back.
- The model is started up while you are still looking at the screen that
  finished the download, and says so, rather than making your first question
  wait for it with nothing on screen.
- Google's terms for the model are shown and have to be accepted before the
  download starts, not linked somewhere afterwards.
- Phones that cannot run it say so plainly — 64-bit ARM only, which is nearly
  every Android phone made since 2018 — instead of offering a 2.6 GB download
  that would fail at the end.
- The welcome screens sit in the middle of the screen rather than pinned to
  the top, and the little dots that show how far along you are can actually be
  seen on a dark background.
- Hold any message in the assistant to copy it.
- Nothing else changes. The online assistant, your provider keys and every
  other AI feature work exactly as before; the on-device model is an option
  beside them, not a replacement.

## v0.9.5

- Notes can be brought in from another app. Settings › Import notes takes the
  `.zip` Google Takeout gives you for Keep — labels become tags, lists become
  checklists, and every note keeps the date it was actually written rather than
  arriving all at once today. Notes you had already deleted in Keep stay
  deleted. It also reads a folder of `.md` or `.txt` files, which is what every
  other notes app exports, so this is not only about Keep.
- Any note can be translated. Open it, tap Translate, and read it in the other
  language — a recording's transcript and the text read out of a photo too, not
  only what you typed. It does not touch the note: copy the translation, or
  keep it as a note of its own beside the original.
- A first launch now walks you around the home screen once — what the button
  does, what holding it does, and where your tags, deleted notes and settings
  are. Skippable from the first step, and it never comes back.
- Ask the assistant out loud. The microphone beside the chat box records your
  question and puts what you said in the box — you read it before it is sent,
  because a name heard wrong is an argument about a question nobody asked.
- Tell the assistant how you want to be answered. Settings › Assistant has a
  line of your own now — "answer with a bit of humour", "keep it short" — sent
  with every question. It changes the tone, not what the assistant is allowed
  to do.
- Text across the app is a step smaller. A card holds what it should, and
  Settings stops running past the fold. If you liked it as it was, Settings ›
  Text & UI size, one step up, is very close.
- Settings buzzes when you touch it. Every switch, row and picker in there was
  the one part of the app the Haptics switch did not reach.
- The greeting and the AI's line are one sentence in one language now — the
  language you wrote your own name in. It was a Persian half glued to an
  English half, full stop at the wrong end.
- The daily summary card keeps its height when it is folded away, instead of
  shrinking to a strip too thin to comfortably tap.

## v0.9.4

- A note with a reminder shows a small bell on its card, so you can see one
  is set without opening the note. It greys out once the time has passed.
- Notes can have a reminder. Open a note, tap Remind, and pick — in an hour,
  this evening, tomorrow morning, next week, or a time of your own. Nex
  brings the note back up as a notification at that time.
- Your reminders survive a reinstall, a restore from a backup and a reboot:
  the time is kept on the note itself and the alarms are rebuilt from your
  notes every time the app starts.
- The daily summary card is one control now: tap anywhere on it to fold it
  away or open it again. Open, it keeps a refresh button; closed, it does
  not — there is nothing on screen for a refresh to change, and the chevron
  was a second control for what the card already does.
- The greeting and the line the AI writes are one line instead of two.
- Nex greets you in the language you wrote your own name in, whatever the
  app's language is set to. "Good morning, سعید" and "صبح بخیر, Sany" are
  both sentences nobody writes.
- The app buzzes where it should: swipes, pickers, opening a note, the
  summary's refresh — and a small tick as the list scrolls under your
  finger. All of it follows the Haptics switch in Settings, which was
  already there and was reaching almost none of this.
- Your website and repository links in About open when tapped. They were
  copying, which made the copy button beside them look like it did nothing
  different.
- Sync is no longer offered in Settings. The server exists and the app can
  talk to it, but there is no way to pair a device from inside the app yet —
  the row asked for a URL and a token nobody has a way to get. It comes back
  when pairing does.
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
