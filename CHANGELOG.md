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

- **Checklist and link cards no longer clip their text at larger UI sizes.**
  The card itself grew with the text size, but the rows inside it were pinned
  to the height of one line at the default size — so turning the size up made
  the card taller while squeezing the words into a slot built for smaller
  ones. Both now grow together.

- **The swipe-action arrows in Settings pointed the wrong way in Persian.**
  Each row shows an arrow for which way your finger travels, and the app was
  flipping those arrows for right-to-left — on top of the flip the system
  already does. Two flips cancel, so in Persian both arrows pointed the way
  they do in English, and the row for the starting edge was illustrating the
  gesture for the other one.

- **Typing quickly no longer leaves half-finished copies of a note behind.**
  The first keystroke is what saves a note — there is no Save button — and
  until that write came back, every further keystroke started another one. A
  word typed faster than the save could land left "h", "he" and "hel" in the
  library as notes of their own, permanently: the sheet only kept the last of
  them, so nothing you did afterwards touched the rest. It took no unusual
  speed — a keyboard that sends a whole word at once, or a paste, was enough.
  Now the first save is the only one, and whatever you typed while it was in
  flight lands on the note it belongs to.

- **The banner that said "The operation failed" now says what failed, and
  why.** One sentence was doing the work of five different failures — a sync,
  a backup, an export, a restore, a recap — and every one of them threw the
  reason away. It named neither the thing that went wrong nor the cause, and
  it is a banner: it is gone by the time you have finished wondering. Each
  now names its own operation and carries what the app was actually told,
  and the full text is kept in the file "Share diagnostics" sends, so a
  failure can still be read after the banner has passed.

- **A restore now says that restored notes stay on this device.** Notes
  brought back from an export are written as already up to date, so sync
  never uploads them — which is fine on the phone you restored onto, and not
  fine if you took it to mean your library was back on the server. The app
  now says so when a sync server is set up. It is a disclosure, not a fix:
  the upload itself is a change to how sync decides what to send, and that
  is worth doing carefully rather than quickly.

- **The app lock now covers the lock screen too.** A reminder's notification
  puts the note's own words in its title, and Android shows them in full on the
  lock screen by default — so a note kept behind a fingerprint was still being
  read out on a locked phone. With the app lock on, reminders are hidden from
  the lock screen and appear once you unlock. With it off, nothing changes:
  hiding every reminder from everyone would take a medication reminder off the
  lock screen of people who never asked for a lock.

## v1.5.1

- **A reminder arriving at the wrong hour is still being looked into.** One
  report has a daily reminder set for 10:00 arriving at 1:10 in the morning, on
  a phone that allows exact alarms, with the note itself still showing the time
  it was given. The cause is not found, so this release does not claim to fix
  it — what it adds is the record needed to find it, below. Until it is
  understood, please do not rely on a reminder for something that has to happen
  on time.

- **Dismissing the clock no longer sets a reminder for nine o'clock.** Backing
  out of the time picker fell through to a default instead of cancelling, so a
  dialog you had just closed set a reminder at an hour you never chose — and
  said "Reminder set" about it. Backing out of the clock now cancels, the same
  as backing out of the calendar one step earlier.

- **Nex now records what it actually asked the system for.** When a reminder
  arrives at the wrong hour there is nothing to look at: the note still shows
  the time you set, and the alarm queue can only say an alarm exists, not when
  it is for. Every reminder now writes the exact moment, time zone and alarm
  precision it was given into the diagnostics that **Settings → About → Share
  diagnostics** sends.

- **A note's reminder can no longer collide with the update notification.**
  Every reminder gets an id derived from the note it belongs to, and a small
  block of ids is reserved for the app's own notifications. When the update
  download took the fourth of those, the arithmetic that keeps reminders out
  of the block was still only skipping three — so a note landing there took
  the download's id, and the two would have replaced each other silently. Rare
  by construction; wrong every time it happened.

- **A malformed release tag no longer breaks the update check.** A version
  number too large to hold threw where it was supposed to answer "no update",
  which would have stopped every install from seeing updates until the tag was
  renamed.

- **A shared video's cover is a fraction of the size it was.** It was encoded
  the way a PDF page is, which is right for a page of text and wrong for a
  photograph — the same frame is a few hundred kilobytes now instead of
  several megabytes.

- **Previews no longer draw on the thread that draws the app.** Rendering a
  PDF page or pulling a frame out of a video happened on the main thread, so a
  large file could freeze the interface while it worked — long enough, on a
  big one, for Android to offer to close the app.

- **The timeline stops re-reading its settings on every card.** Whether a card
  is shown in full was read back out of storage once per card per frame,
  rebuilding a list and a set each time to answer a question about one note.

## v1.5.0

- **A reminder can be set while you are still writing.** Once you have typed
  something, an alarm button appears beside the send button — one tap, pick a
  time, carry on typing. Nothing has to be decided before you start: the button
  is not there on an empty sheet, and by the time it is, what you typed has
  already been saved.

- **The home screen can show only what has a reminder coming.** The filter
  behind the icon on the tag row has a **Has a reminder** row under the note
  kinds. It layers on top of them rather than replacing them, so "photos with
  a reminder" is a thing you can ask for — and a reminder that has already rung
  and been seen drops off by itself, so what is listed is what is still ahead.

- **A video shared into Nex shows a frame of itself.** Until now a shared video
  was a filename and a size, which is nothing to recognise a clip by. It gets a
  cover now — a frame from a second in, past the fade a lot of video opens with
  — and tapping it hands the file to whatever plays video on your device, which
  is where scrubbing and volume belong. Android only for now, the same as the
  PDF preview and for the same reason: it uses what Android already has instead
  of adding a video engine to the app.

- **The changelog on About is a card of its own.** It arrived as ten releases of
  text down the page, which put everything under it a long scroll away. It is a
  bounded card now that you scroll through without scrolling the page.

## v1.4.0

- **A file you share into Nex is shown, not just named.** Markdown already
  opened inside the note; now a plain text file, a spreadsheet exported as
  `.csv` or `.tsv`, and a source or configuration file do too — each read the
  way it should be read, so a text file is not mistaken for Markdown and a
  table arrives as a table.

- **Music plays inside the note.** An `.mp3`, `.m4a`, `.wav`, `.ogg`, `.opus`
  or `.flac` gets the same player a voice note has, instead of being a
  filename and a size.

- **A picture shared as a file looks like a picture.** The same photo used to
  look completely different depending on whether it was taken in the app or
  shared into it; now either one opens full screen from the same tap.

- **Text you write can be formatted.** Select a word while writing or editing a
  note and the menu that already offers Cut and Copy now also offers **Bold**,
  *Italic*, `Mono`, ~~Strikethrough~~, Quote, Link, and Regular to take it all
  back off. A note that has formatting in it is shown formatted when you open
  it; one that does not is shown exactly as you typed it, so an asterisk you
  meant as an asterisk stays one. Timeline cards and reminders show the words
  without the marks.

- **Tap a `mono` word to copy it.** Inside an open note, one touch on a span
  you set in monospace puts it on the clipboard and says so. Links inside a
  note — and inside a Markdown file opened in one — are tappable now too, and
  the whole body can still be selected by dragging across it.

- **Word documents open inside the note.** A `.docx` shared into Nex is read
  and shown the way everything else in the app is written: headings, bold,
  italic, strikethrough, lists, quotes, links and tables all survive. What Word
  can express and this cannot — fonts, colours, columns, images — does not, and
  the file itself is still one tap from whatever opens it properly. A very long
  document shows its beginning and says that is what it is showing.

- **A PDF shows its first page.** Enough to tell one report from another at a
  glance; tapping it hands the file to whatever opens PDFs on your device,
  which is where searching and turning pages belong. Android only for now —
  it uses the renderer Android already has rather than adding several
  megabytes of one to the app — and elsewhere the file is named as before.

- **Fixes a bug that deleted your profile picture.** The background clean-up
  that removes attachments left behind by deleted notes was looking through
  every folder under the media directory, and the profile picture lives in one
  of them. No note pointed at it, so it was treated as a leftover and removed.
  It now only looks where a note's attachments are actually written. A picture
  already lost cannot be recovered — it has to be set again.

- **The reminder test row is out of Settings again.** It was taken out once on
  purpose and came back in an imported change nobody meant to include.

- **A stopped update download stays where it stopped.** It used to throw the
  whole screen away and replace it with a full-page error whose button started
  the check over. Now it says so in a line under the progress bar, with a
  Resume beside it that picks the transfer up from the byte it reached — the
  part already downloaded is kept, not fetched again. Running out of space
  says that instead, because that one you have to go and fix.

- **Reopening the update screen during a download shows the download.** It was
  still running the whole time — leaving never stopped it — but the screen
  showed a Download button as though nothing was happening.

- **The update screen shows only the version it is offering.** The full history
  of every past release is no longer stacked underneath a question about one
  build — it moved to About, where the last ten releases are listed on the page
  rather than in a small box that scrolls inside itself.

- **The download shows up in the notification shade.** While an update is
  downloading there is a progress notification you can watch without opening
  Nex — and swipe away if you would rather not, which does not stop the
  download. When it finishes, the same notification says so, and tapping it
  opens the update ready to install.

- **A note can stay open on the timeline.** Cards show two lines, which is
  right for almost everything and wrong for the one checklist you need in
  front of you. Open a note and choose **Show in full**: that card grows to
  fit all of it — every item of a checklist, every line of a note — and stays
  that way until you put it back. Every other card is unchanged.

- **There is a guide now.** Settings opens with **How Nex works** — a short,
  friendly walk through everything the app does, from writing a note to adding
  an API key to changing the theme. In English and Persian.

- **The first-run introduction covers more of the app**, and ends by pointing
  at that guide, so nothing has to be discovered by accident.

## v1.3.2

- **A swiped-open card takes the next tap, whatever it lands on.** Tapping
  another card already only put the open one away, but the date headings did
  not know that yet — so a tap meant to close a card also folded the group it
  was in. Nothing on the screen acts while a card is waiting: the touch puts
  it away, and that is all it does.

- **Old attachments left behind by deleted notes are cleared out.** Until
  1.3.0, emptying the trash removed the note but left its photo or recording
  on the device for good. Deleting takes the file with it now, but that does
  nothing about what earlier versions already left — so Nex sweeps those up
  in the background, once a day, and only ever removes a file no note points
  at any more.
- **Swiping back no longer flashes through to the page underneath**, and a
  swipe in the wrong direction no longer makes the page transparent for as
  long as you hold it.
- **Settings rows have more room between them.**

## v1.3.1

- **Fixes a crash that stopped 1.3.0 opening at all.** On every launch Nex
  reported that it could not open your local library and offered to try
  again, which could not help: the fault was in the code that opens the
  database, not in the database. Your notes were never touched — the library
  was never reached, let alone changed. If you are on 1.3.0 you will need to
  install this one by hand, because the in-app updater lives behind the
  screen that will not open.

## v1.3.0

The reliability release. Most of it is the app refusing to lose things or lie
to you — the same instincts as 1.2.6, turned toward the parts that had to be
trusted instead of seen.

- **"Delete forever" now deletes forever.** Emptying the trash (or purging a
  note from it) removed the database row but left the photo, recording or
  attachment file on disk for good — still swept into every backup. The file
  goes with the note now.
- **Reminders stop outliving their notes.** Deleting a note left its alarm
  armed in the OS, so it still fired — and re-armed after every reboot.
  Restoring a backup left ghost alarms for notes the restore had removed.
  Both are cleaned up now, undoing a delete brings its reminder back, and
  editing a note refreshes the text of its pending notification.
- **A one-off reminder clears itself once it has rung.** It used to stay on
  the note for good — the card stopped showing it, but the note still carried
  a reminder and the only way to be rid of it was to open it and press
  Remove. A reminder is a thing to be reminded of, and once it has happened
  it is finished. Repeating reminders are untouched: a daily or weekly one is
  never spent, because it is always about to ring again.
- **A reminder series can no longer retire itself.** A daily reminder whose
  start had drifted more than about two years into the past stopped being
  rescheduled at launch, silently. The next occurrence is now computed
  directly instead of stepped day by day.
- **A failed transcription, OCR pass or embedding no longer burns its slot.**
  One timed-out request used to permanently mark a voice note "no transcript"
  or hide a note from semantic search. Failures now leave the slot open for a
  retry; only a real answer — including "nothing was heard" — closes it.
- **Nex never invents a transcript.** With AI on but no provider configured,
  voice and photo notes received fabricated text and it was stored, searched
  and shown like the real thing. It is not produced any more.
- **Your library no longer rides Google's cloud backup.** Android's automatic
  backup silently uploaded the whole database to Google Drive — and without
  its write-ahead log, which is how a restored copy can come back corrupt.
  Nex keeps its own backups, on the device, where the data was always meant
  to stay.
- **Search filters finally have buttons.** Tag, type and date filters existed
  under the hood but were reachable only by typing `tag:` and `type:` into
  the search field. A filter button beside the field opens a sheet of chips
  that combine and apply as you tap.
- **A failed first read of your timeline says so, with a retry** — instead of
  showing skeletons until you gave up.
- **The app survives a database it cannot open.** The failure is named on
  screen, and if you have a backup file, a Restore button right there will
  put your library back without the app ever having to open.
- **Backups restored onto a reinstall find their files again.** A `.nexbak`
  restored into a new sandbox used to keep pointing every photo and recording
  at the old device's paths. Media paths are rewritten to where the files
  actually landed.
- **Restores that fail say so.** A failed restore used to brick the session
  silently; it now reports what happened.
- **The Gemini API key moved out of the request URL** into a header, so it
  stops appearing in anything that logs request lines.
- **The exact-alarm permission screen is shown once per install**, at the
  first reminder, instead of teleporting you to system Settings every time
  you set one.
- **A test notification row in Settings** — one notification now and one in
  ten seconds, to tell "Nex never sent it" from "my phone swallowed it".
- Smaller honesty: the trash shows when a note was deleted instead of
  repeating its type; a filtered timeline says notes are hiding behind your
  filters instead of claiming the library is empty; the update-available dot
  is visible to screen readers; the AI recap says when its refresh failed;
  the on-device chat prompt finally receives its scope ceiling.

## v1.2.7

- **Starting Nex for the first time lets you write straight away.** A fresh
  install opened on five pages of introduction, then a name it would not go
  past, then a four-stop tour laid over the screen — all before there was
  anywhere to put a thought. Skip now finishes rather than jumping to the one
  page it could not leave, the name is optional, and the walk-through waits
  until there is a note to point at, so it can show you where what you just
  wrote went instead of describing an empty screen. Nothing was removed: the
  pages are still there for anyone who wants them, and every choice on the
  setup page has always lived in Settings too.
- **The assistant no longer says "Done." when nothing was done.** If it named
  a note that was not there — one it had misremembered, or one already
  deleted earlier in the same conversation — the change quietly matched
  nothing and it reported success anyway. Every note an action names is
  checked before any of it runs.
- **The switches are smaller.** They were the loudest thing on a settings row.
  Tapping anywhere on the row still works, so there is more to aim at than
  there was before, not less.

## v1.2.6

Mostly a round of the app telling the truth: several controls that did
nothing, said nothing, or said the wrong thing now report what actually
happened.

- **The microphone button says why it did nothing.** Refuse Nex permission to
  record once and both voice capture and the assistant's dictation went
  silently inert for good — no sheet, no message, no reason. They explain
  now, and say where the permission can be given back.
- **Four screens no longer claim to be empty while they are still loading.**
  Tags, Recently Deleted, Backups and a note opened from the timeline all
  rendered before their first read came back, so "no tags yet", "nothing in
  the trash", "no backups" and "note not found" were what you saw for as long
  as the read took, and then the real thing appeared. On the screens that
  exist to reassure you your notes are safe, that is a wait told as loss.
- **Summarize appears only where it can work, and says when it cannot.** It
  was offered on every note, including with summarization switched off or no
  provider set up, and in all of those cases tapping it did nothing at all.
- **A search that fails says so, with a way to try again.** If the search
  itself errored, the results area kept showing placeholder cards for ever
  and leaving search was the only way out.
- **Empty trash is no longer offered before the trash has been counted**, and
  **Merge no longer appears on your only tag**, where it opened a list of
  every other tag — that is, nothing.
- **A finished model download no longer announces that offline chat works
  when the model would not start.** The screen showed the reason underneath
  at the same time, which is two answers to the same question.
- **The search box is one box again, and the strip of colour under it is
  gone.** A second frame was being drawn inside the rounded field, in both
  its resting and typing states, and the row itself sat on a band of flat
  colour laid across whatever background you had chosen.
- **The top bar is frosted under the glass appearance instead of merely
  see-through.** It was a half-transparent tint with no blur behind it, so
  what sat behind it stayed perfectly readable, only paler.
- **Pages no longer go transparent on the way in and out.** The previous
  release fixed this for the back-swipe; entering and leaving a screen is an
  animation rather than a gesture, and went on briefly showing two pages
  through each other every time.

## v1.2.5

A round of fixes to the glass appearance, to how text finds its own
direction, and to the surfaces both of them touch.

- **The glass appearance is frosted now, not see-through.** It was tuned like
  a pane of glass — half transparent, a bright rim, a diagonal sheen — so
  whatever sat behind a surface stayed readable through it and text landed on
  text. The blur is heavier, the tint carries text at full contrast, the sheen
  is gone and the edge is a hairline. Depth comes from the blur, not from
  letting you read the layer underneath.
- **Sheets have a surface of their own again.** Under the glass appearance a
  sheet was drawn fully transparent, on the assumption that every one of them
  wrapped itself in a glass panel — and most do not, so the reminder picker
  and the chat history were painting their text straight onto the timeline.
- **The page no longer goes see-through mid-swipe.** Sliding a screen back
  revealed the page underneath *and* kept the moving page transparent, so for
  the length of the gesture both were legible at once.
- **Switches are smaller.** Material draws one at 52x32 and then pads it to a
  48-pixel target on every side, which made it the loudest thing on a
  settings row; the tick inside the thumb is gone with it.
- **A reminder that has rung now clears itself when you put the app away.** It
  was only cleared by opening another screen first, so anyone who read the
  note and closed the app kept the chip until they deleted the reminder by
  hand.
- **Mixed Persian and English no longer flips as you type.** Direction was
  decided by counting: once enough of a note was Persian, the whole box —
  English lines included — swung right, at some keystroke nothing announced.
  The same note then sat on the timeline aligned one way or the other
  depending on how much of each language it happened to contain. The first
  letter decides now and nothing after it does, which is the rule Unicode
  specifies and the reason nothing moves while you write.
- **Tone is one control instead of two.** The five response styles and the
  free-text instruction were both about how the assistant sounds, so picking
  "Formal" and writing "be witty and sarcastic" left nothing to say which one
  won. "Custom" is now the sixth style — the one you write yourself — and the
  box appears under it. Your sentence is kept either way, so switching to a
  preset and back does not ask for it again. An instruction written before
  this still works: it is read as a custom style rather than quietly dropped.
- **The daily summary lines up in Persian.** Its icon and its text were placed
  with left-and-right padding rather than start-and-end, so in a right-to-left
  layout both stayed pinned to the side they were written for and sat out of
  step with everything around them.
- **The search box is one box again.** A second, filled frame was being drawn
  inside the rounded field — the app's own input styling landing on top of the
  one the field already had.
- **The tag row only takes a background when it needs one.** It carried a band
  of colour at all times, which showed as a stripe across a chosen background
  image. The band now appears when the row actually sticks to the top of a
  scrolling list, which is the moment it has something to cover.

## v1.2.2

- **A new optional Liquid Glass appearance sits beside the existing light and
  dark themes.** It uses adaptive translucent surfaces, real background blur,
  restrained edge highlights, and softer press feedback while preserving an
  opaque high-contrast fallback. Four built-in minimal backgrounds — Plain,
  Aurora, Ripple, and Weave — work independently in either theme.
- **Profile and assistant preferences are now complete screens.** A profile can
  hold a local photo, name, birthday, and bio; the assistant can learn what to
  call you, a short introduction, and a response style including Romantic.
- **Nex can lock itself with the device credential or biometrics.** The lock is
  local to the device and returns whenever the app leaves the foreground.
- **Navigation and reading are more consistent.** Swipe-back reveals the page
  underneath, Persian and English lines align by their own script, date-group
  headings share the timeline gutter, and up to five notes can now stay pinned.
## v1.2.1
- **Reminder and daily-nudge controls work again in release builds.** The
  Android optimizer was removing the notification icon because its keep rule
  lived in the wrong resource folder. The notification service could not
  start, so both controls appeared to ignore taps even though nudges scheduled
  by an older version kept arriving. The icon is retained now, and release
  builds refuse to publish if it disappears again.

## v1.2.0

A small round of fixes to make reminders more reliable.

- **Reminders no longer initialise twice at the same time.** Two parts of
  Nex could ask the reminder service to start together, racing each other and
  doing the same setup twice. Initialisation is shared now, so the second
  request waits for the first instead of starting another one.
- **Notification permission is checked after Android answers.** The immediate
  result of a permission request can say "no" simply because the system has
  not returned the user's answer yet. Nex now reads the actual permission state
  after the request finishes, so a reminder is not incorrectly treated as
  unable to use exact alarms.

## v1.1.0

The first round of fixes from v1.0.0 in real use.

- **The assistant's own protocol stopped leaking into the chat.** Asked to
  make a note, it answered with `{"action": "create", ...}` as visible text
  and made nothing. An unfenced action had to *be* JSON, so one emoji in front
  of it broke the parse — and the emoji was there because v1.0.0 had just
  asked the assistant to use them. Any JSON object in a reply is found
  now, wherever it sits, and the protocol says plainly that a reply carrying
  an action carries nothing else.
- **Reminders: the exact-alarm state is no longer thrown away every time one
  is set.** Asking Android for the permission opens a settings screen and
  returns "no" on the spot, because the user has not answered yet — and that
  "no" was being stored as the answer, putting every alarm back on the
  inexact path v1.0.0 had just taken it off. The state is read back
  instead. A reminder that cannot be scheduled now says why, in the system's
  own words, rather than a sentence nobody can act on.
- **A note's sheet grows with the note.** Past 220 characters it used to jump
  to two thirds of the screen and leave the bottom third empty under its own
  last line. There is no step now; it is as tall as what is in it.
- **The date heading's menu**: a horizontal ellipsis, level with the chevron
  beside it, opening a rounded menu instead of a square one.

## v1.0.0

Nex reaches 1.0. Reminders that arrive and repeat, an assistant you can
reach and tune from the conversation itself, a home screen you decide the
shape of, and a storage figure that tells you the truth.

- **The daily note arrives when you asked for it.** Set for seven, it came at
  twenty past — an inexact alarm, which Android is free to batch, and the same
  mode already proven wrong for note reminders and fixed there. Worse, the
  flag deciding exact-versus-inexact was only ever set while *asking* for
  permission, so every launch quietly re-armed every alarm — reminders
  included — as inexact regardless of what the phone actually allowed. The
  state is read at startup now, and the daily note is scheduled exactly. If
  the phone refuses either the permission or the alarm, the switch says so
  instead of sitting on.
- **And it no longer says your library is empty.** Its text is fixed when the
  alarm is set, and it read the day's recap through a gate that only opened if
  the summary had been written *today* — which, at seven the next morning, it
  never has been. So it fell back to "nothing written down yet today", every
  single morning, to people with hundreds of notes. It carries the last recap
  there is now, which is yesterday's, which is the useful thing for a morning
  greeting to be carrying.
- **Tagging a note no longer moves it to the top.** The timeline puts an
  edited note first, which is right — it is the one you were just working on.
  Filing one under a tag was doing the same thing, and it is not the same
  thing: the note still says exactly what it said.
- **Fixes found reviewing this release.** A swipe-back on a screen that
  declines to close left the page sitting where the finger let go, with the
  gesture dead for the rest of its life. A repeating reminder stopped coming
  back after a reboot, and wore "Overdue" on its card between firings — it is
  never overdue, and now says how often it repeats instead.
- **Reminders can repeat.** Every day, or every week, chosen beside the four
  shortcut times rather than instead of them — a repeating reminder still has
  a first firing, and the confirmation names both. A repeat is cleared when
  the reminder is.
- **Storage, rebuilt into something you can act on.** The row said "41 MB"
  and stopped — a number nobody can do anything with, and the wrong number
  besides: it left out the offline model, which on an install that has one is
  larger than the notes, photos and backups put together. It is now the real
  total, a proportion bar, and the parts: offline model, photos, recordings,
  backups, notes and index.
- **The assistant's settings, rebuilt and reachable from the chat.** They were
  one flat column of five section titles with nothing saying which went with
  which; they are three groups now — how it talks, what it can see, and your
  standing instruction — in the same cards Settings uses. A control in the
  chat's own header opens them over the conversation, which is where you
  actually notice one needs changing.
- **The chat rises to meet the keyboard.** Tapping the composer takes the
  sheet to full height instead of leaving the thread squeezed into whatever
  the keyboard left.
- **The history and settings panels close with a downward swipe**, from
  anywhere in them rather than only from the handle.
- **Holding the capture button lights a spectrum, not the accent.** Tapping
  that button and holding it are different things, and lighting the same blue
  for both said they were the same.
- **A warmer assistant.** It may use an emoji where one does real work — at
  most one per line, never inside a sentence.
- **A spent reminder stops shouting.** A reminder still ahead keeps its chip
  on the card — that is what it is for. One that has already rung gets one
  last showing, and then the slot goes back to the note's own timestamp
  instead of wearing "Overdue" for ever.
- **A layout control in the app bar.** The greeting, the smart daily summary,
  the search box and the tag row can each be switched off — all four are the
  app's idea rather than yours, on a screen whose subject is the notes under
  them. Turning the search box off brings its app-bar icon back.
- **Date headings can act on their whole run.** A menu beside the chevron
  deletes the day's notes in one go, after asking, or opens the assistant with
  just that day as its context. The menu is outside the heading's own tap
  area, so reaching it never folds the group on the way.
- **A tapped reminder now points at its note.** It opened the app and stopped
  there — the notification named the note and the timeline showed the same
  list it always shows. The card is scrolled into view and its border pulses
  twice, including when the tap is what started the app.
- **Swipe back from anywhere.** Every screen with a back arrow could already
  be dragged shut, but only from a 20-pixel strip at the very edge — the same
  far corner the arrow is in. The whole page answers now, mirrored for
  Persian, and a row of chips inside it still scrolls on its own.
- **A long note's sheet closes by dragging it down**, not only by its handle.
- **The bottom of the home screen no longer fights Android's gestures.** The
  list drew and listened all the way down, so a swipe up from the bottom edge
  was a coin toss between scrolling and going home.
- **Reminder times fit on the card again.** A note due in thirteen hours was
  spending most of its line saying so, and pushing its own words off the end.
  It now says `13h`.
- **The reminder notification carries the app's mark**, not a white square.
  Android silhouettes a status-bar icon, so the launcher artwork came through
  as a solid blob.
- **A quieter home screen.** The daily digest card and the search field sit
  flatter against the page, tag chips are outlined only while they are on,
  and tapping a date heading no longer flashes a filled block behind it.
- **Fewer switches in Settings.** "Reduce motion" is gone — the app already
  follows the system's own reduced-motion setting, and the two of them
  disagreeing was the only thing the switch added. The test-notification row
  is gone with it, and capture haptics moved up into Capture where it belongs.
- The Persian for the export screen's title said "output" in the arithmetic
  sense.

## v0.9.9

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
