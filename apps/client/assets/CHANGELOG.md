# Changelog

User-facing release notes. Detailed technical history is preserved in [the development archive](docs/development/CHANGELOG.md).

## v2.6.18

- **More readable surfaces.** Stronger contrast for vault bank cards, banners, module icons, tags, switches and urgent markers across Light, Dark and Night.
- **Better Persian typography.** More comfortable line height, legible counters and consistently sized attachment badges.
- **Quieter motion when requested.** Reduced-motion settings now apply to pages, sheets, camera, onboarding and loading indicators.
- **Clearer, gentler feedback.** Unified touch feedback for reminders, checklists and switches; faster banner exits, smoother filters and more efficient reminder-bell animation.

## v2.6.17

- **Larger files, clear refusals.** Ordinary attachments now allow 500 MB; oversized or unreadable selections explain why they were not imported.
- **Untagged appears only when useful.** The filter hides when every timeline note has tags and clears an empty active selection.
- **Undo keeps its promise.** Permanent trash deletion waits until its Undo actually closes, and AI edits keep an Undo button in compact editors.
- **Capture preserves unsaved work.** Failed writes stop media handoff; failed conversions keep the original reminder and retry without duplicating the converted note.
- **Reminder taps survive the lock.** Recurring reminders open their destination after unlocking.

- **Editing continues at the end.** Notes, captions and attachment captions open with the caret after the existing text.

- **Assistant answers use real library totals.** Counts come from the database; internal searches stay out of replies and interrupted cloud answers get one bounded retry.

- **Bottom navigation is easier to see.** A subtle outline and a distinct background separate the dock from content in Light, Dark and Night.
- **Navigation returns quietly after capture.** Closing capture restores the dock without the rotation and zoom animation.
- **Restore checks compatibility before changing your library.** Older supported libraries are upgraded on a temporary copy; incompatible or malformed backups leave the current library untouched.
- **Interrupted restores keep a recovery path.** Library, media and full-backup settings can return to the previous state; cleanup failures after a successful restore no longer report failure or stop the app opening.
- **A healthy backup can repair missing files.** Missing photos in the current library no longer prevent restoration, and the safety copy records which files were already missing.
- **Backup files keep their meaning when shared.** A library backup renamed to `.zip` is recognized, and shared rescue backups retain their missing-file report. Invalid appearance settings are rejected before installation.

## v2.6.16

- **An Undo can no longer be swallowed silently.** A plain banner arriving while an actionable one is still up waits its turn instead of eating it — and a banner replaced by a newer one leaves through the edge it came from, with its exit animation.
- **Banners keep their own time.** They arrive in half the time they used to, their words are readable from the first third of the entrance, the countdown starts once the entrance is over, scales with the message's length, and holding a banner pauses it.
- **Sending a note reads as success.** The capture sheet leaves as soon as the words are settled — the timeline reloads behind the closing animation — and the send button becomes a ✓ rather than greying the sheet out like a failure.
- **The first keystroke changes no sizes.** Paste keeps its column with only its icon fading, and the schedule hint waits for the words to be still, so nothing jumps around under the arriving keyboard.
- **Paste shows when there is something to paste.** The sheet asks — without reading the clipboard — on open and on return, so an empty clipboard no longer shows a button that visibly does nothing.
- **A link's Open sits on the toolbar.** Each note kind's primary action — Open for links and files, Edit for text — takes the first slot by rank, not by matching translated labels, which is why Open always used to hide behind More.
- **Long notes open the editor full screen.** Past about eight lines the editor owns the screen from the start instead of a 220px box, and ✕ and ✓ are its controls in either size.
- **Pickers arrive like the rest of the app.** The time and date pickers rise and settle on the app's own beat and scrim rather than Flutter's flat 150ms fade, and the assistant's settings sheet is the app's own sheet again.
- **The camera's wait is spoken.** While the sensor is being asked for, the panel shows a faint skeleton and says what it is doing — and six seconds in it offers the phone's camera app, before the timeout does.
- **Covered, not cleared.** Pulling the shade over the vault lays a blur across it and comes straight back with the form as it was — words, caret and place — instead of rebuilding it from a draft; being away past the grace period still locks.
- **The assistant hold hint gets a button.** "Got it" is a real button now rather than part of the sentence, and the hint keeps to the app's own label style — still shown only when the assistant can actually answer.
- **A toast leaves the way it arrived.** Its content's exit — a small settle and fade on the exit token — completes the entrance it always had.
- **A cut preview says so.** A multiline bilingual preview that runs out of rows ends in an ellipsis instead of reading as the note's ending, and blank lines are no longer spent from the budget.
- **A fast retreat is not a flick.** Pulling back through the middle to cancel a capture flick no longer fires the opposite side's shortcut; the opposite side still works by crossing its full arm.
- **The wide-window scale is said out loud.** Appearance now notes that a wide window draws everything at 90% of the chosen size — the factor was always there, silently, on the notes' own text too.
- **One clearance rule for the dock.** A single helper reserves the capture dock's room instead of the same sum written out screen by screen, and the dock itself gives way under an open keyboard.
- **Chosen Night hands over in black.** With Night chosen, the window between the system splash and the app's first frame is painted black instead of flashing Soft Dark's grey.

## v2.6.15

- **A tap in the search field is no longer a re-run.** Touching the field to move the caret or paste no longer restarts the whole search and re-fades the results; the keyboard's Search key now actually runs the query instead of just closing the keyboard.
- **Leaving search keeps your words.** With text typed, a touch outside the field now only lowers the keyboard — it never wipes the query. Clearing stays on the ✕ and Back.
- **One buzz per delete.** Deleting a note used to vibrate three times in a row (gesture, action, banner). Now the one confirming buzz is the whole receipt.
- **The assistant hold hint waits until it is true.** The "Hold + for the assistant" pill no longer appears for users whose assistant cannot answer yet.
- **A quick double-tap on Save no longer closes the page beneath.** The checklist editor's buttons are latched during the exit animation, like the capture sheet's.
- **Restored checklist drafts open with the caret at the end**, not in front of the first character — and swiping the editor down now asks before discarding, instead of silently keeping the text in drafts.
- **Checklist lines follow their own language.** In mixed Persian/English lists, each checkbox now sits beside the start of its own line on cards and in the detail sheet.
- **Enter in the assistant chat makes a new line.** The send button beside the field is the only thing that sends; on a physical keyboard Enter still sends and Shift+Enter breaks the line.
- **A note of nothing but spaces no longer leaves a card behind.** Saving a note of nothing but spaces now discards it, instead of leaving an empty card to delete by hand.
- **The chosen expense category stays in the row** even in a month that has none of it, so a stray filter can always be lifted.
- **Leaving the photo cropper asks only when something changed.** Waiting for the photo to load is not an edit.
- **Crop and annotation failures look and sound like failures** — a proper message in your language, not a success-styled banner with a raw exception in it.
- **PDF page arrows follow the reading direction** in Persian, agreeing with the swipe instead of arguing with it.
- **Smaller controls reach the 48dp touch floor.** The Undo banner's button and the voice speed chip now meet the app's own minimum touch size.

- **Passwords in the vault are masked.** The editor dots them while typing and the list dots them at rest; the eye beside either lends the real characters for a few seconds and covers them again by itself.
- **The editor's caret starts where the words start.** Opening a note no longer drops the caret after the last character; a recovered draft still opens with the caret at its end, where typing left off.
- **Merging tags says what it will do before it does it.** Both names and how many notes follow, with a receipt naming the tag that kept them — the same confirmation deleting a tag always had.
- **Back lifts the timeline's filter before it leaves the app.** A filtered list used to survive the Back key: now Back takes the filter off first, and only a second Back exits.
- **A pin says so, and shows the way.** Pinning from the menu or a swipe raises a short banner whose action scrolls to the pinned cards — and the five-pin limit now offers the same trip instead of a bare refusal. The button in the note sheet keeps its word, "Pin", and says the limit only when pressed there.
- **Capture keeps its buzzes to one per event.** The sheet's failure banners respect the haptics setting, a broken journal is announced once per sheet rather than per keystroke, and a capture that converts to a list or link no longer buzzes twice.
- **The day summary folds under a real scroll, not a tremble.** Four pixels used to close it — and save the closure for every launch after; now it takes a finger-dragged 56, lasts the session, and the preference belongs to its own chevron.
- **A typed complaint is guarded like typed words.** The feedback sheet asks before Back, a swipe or a tap outside closes over what was written.
- **Removing a tag from a note can be undone.** The ✕ now leaves a banner: the tag's name, and an Undo that puts it straight back.
- **Several tags in one visit.** The tag picker takes ticks in place and one Add commits them all — three tags on a note no longer cost three rounds of open, pick, wait for the close.
- **Technical tags read as themselves in Persian.** `C++`, `#work`, `v2.0!` keep their own order on the timeline's filter pills instead of coming out reversed.
- **One receipt for every copy.** The hold menu, the note sheet and the selection all use one voice; Android 13+ leaves the word to the system's own clipboard preview, and everywhere else the banner says it.
- **The hold menu answers the hold.** A tick when it opens, the card ducks a hair while it is up, and the menu hangs from the card's top edge rather than from under the finger.
- **Copied text is only the text.** Empty lines copy as lines, not as invisible zero-width spaces, and neighbouring lines whose boxes touch no longer glue together with spaces.
- **Home's tag filters take effect at once.** Tapping a tag, type or reminder filter now updates the notes on screen in the same breath; they used to keep showing the previous selection until something else rebuilt the screen.
- **Home's tag counts count Home.** The number beside a tag says how many notes on the timeline carry it — archived and set-aside notes no longer inflate it.
- **Code blocks read left-to-right inside Persian notes.** Fenced code in a Markdown note keeps its own direction, alignment and horizontal scrolling instead of being reordered by the note's Persian layout.

## v2.6.14

- **Working tag filters in search.** The Tags row finally appears in the search filter sheet, typing `tag:` finds your tags, and several chosen tags now mean "any of them" — the same as the timeline's filter chips.
- **An honest Undo in the trash.** Leaving the trash after deleting a note for good no longer leaves an Undo banner that cannot bring it back.
- **Reading an AI answer or a translation no longer closes the note.** Scrolling a long result inside its box stays inside the box, instead of taking the whole sheet with it.
- **Delete works from a recurring item's linked notes.** Deleting a linked note there now moves it to the trash with an Undo, instead of quietly doing nothing.
- **A friendlier link capture.** Pasting text that is not an address no longer dead-ends: Send keeps it as the note it already is and says so, a Clear button appears, and the "not a link" hint waits until you stop typing.
- **The back gesture keeps a recording in progress.** Leaving the recording sheet the way Android goes back now keeps the recording — the same as Stop — instead of throwing it away.

## v2.6.13

- **Faster opening of long notes and text files.** The first page appears with the detail sheet instead of waiting for it to finish opening.
- **Smoother reading and actions.** Long documents reveal progressively and keep menus and scrolling more responsive; Markdown blocks and whitespace stay intact.

## v2.6.12

- **Smoother returns from Settings and Recurring.** Unchanged recurring commitments no longer trigger a full Home screen redraw when closing these pages.
- **Reliable recurring updates.** Changes to schedules, completion history and attached details still appear, and today's completion counts refresh correctly after midnight.

- **Smoother navigation throughout Nex.** Unchanged screens in Threads, Library, Set Aside, note details, Home layout, and Intelligence no longer redraw unnecessarily after returning.
- **Real changes remain visible.** Notes, tags, attachments, and thread membership continue to update when edited.

## v2.6.11

- **Smoother return to Home.** Closing note details or returning from another page avoids unnecessary timeline rebuilding when nothing has changed.
- **Reliable note updates.** Actual changes to notes, reminders, tags and AI-enriched content continue to appear, even while filters are active.
- **Tidier circular note markers.** Reminder, urgent and attachment indicators now sit precisely on the main icon's rim rather than overlapping its centre.

## v2.6.10

- **Smoother scrolling with long notes.** Timeline previews now do far less work when a note contains lengthy text or Markdown, so the list responds more smoothly.
- **Lighter expand and collapse.** Opening or closing groups of long notes is faster, without changing the full contents of your notes or their appearance.

## v2.6.9

- **Precisely aligned note badges.** The centres of tag dots above and attachment, priority and reminder badges below now sit on the full-size note icon's actual circular rim. The main icon stays the same size even with multiple badges, and spacing adapts to the card density.
- **Three tags, without losing your data.** New notes cannot take a fourth tag. Older notes keep existing extra tags until you remove them in note details. Imports with more than three distinct tags on a note are rejected before saving any notes, with a clear warning rather than silently discarding tags.

## v2.6.8

- **A clearer capture button.** The + stays white on Nex blue while custom accent colours keep a legible icon.
- **Clearer timeline cards.** Circular note icons now show tag colours above and reminder, urgent and attachment marks below. Selection and ringing reminders use the same circle; selecting a ringing note acknowledges it without deleting its reminder.
- **More readable navigation and filters.** Tag filters show quiet note counts, while the floating navigation bar gets a fine outline and soft shadow.
- **Liquid Glass temporarily paused.** The option is disabled while its appearance is refined; the saved selection remains intact.

## v2.6.7

- **Night is now true OLED black.** A pure-black page, charcoal cards and softer text give Night its own quiet look.
- **Light feels calmer.** A white page and gentle grey cards make notes easier to scan, without decorative card borders or shadows.
- **Clearer fields and matching Android colours.** Text fields keep a slim visible outline; Android launch and home-widget colours follow the new look. Your accent, Liquid Glass and accessibility settings still work.

## v2.6.6

- **Soft Dark and a familiar Night.** Dark uses calm blue-grey surfaces and softer text, with fewer decorative borders and shadows. Night keeps the former dark look; System follows your device using the new Dark. Existing dark selections become Night. Custom accents and Liquid Glass remain available.
- **A steady Nex appearance.** Preset themes are temporarily unavailable while the main Nex look is refined; their saved choices are kept.
- **Correct note order in threads.** Notes stay in chronological order even when their saved timestamps have different precision.

## v2.6.5

- **Rescue library backups.** Keep recoverable notes and files even when some attachments are missing, with a clear missing-file list. Normal backups keep their complete-file checks.
- **More responsive libraries.** Capture stays available during sync network waits, and smart search does less repeated work in large libraries. Card status icons sit closer together with a consistent small bottom gap.

- **Complete private-vault backups.** Choosing Include private vault now carries its encrypted photos, recordings and files to the restored device. Large private lists and draft saving are lighter.
- **Safer sync and updates.** Unsent conflicting edits are kept as a separate note. Approved interrupted downloads can resume after restarting Nex; store copies continue to update only through their store. File saving and scheduled-note processing are more reliable.

## v2.6.4

- **Balanced timeline cards.** File names and one-line or multiline previews are vertically centred again. Reminder, attachment and urgent icons appear in that order with tiny separate halos that follow the card's press highlight. Reminder times and attachment counts are temporarily hidden on cards; their data and accessible descriptions remain available.

## v2.6.3

- **More room for your notes.** Timeline previews keep their full width in every card size, including three lines in Large. Reminder, urgent and attachment marks sit over the lower edge with a soft fade, while short notes stay fully visible and captions remain grey.

## v2.6.2

- **Uniform timeline cards.** Collapsed notes keep one height across text, photos, links, checklists and voice. Captions use a quieter preview line; reminder, urgent and attachment marks stay together in a separate area without empty slots.

## v2.6.1

- **A more useful smart summary.** Pending work, reminders and important notes take priority; routine completed habits no longer crowd them out.
- **Calmer capture and easier translation.** Paste fades smoothly as its space closes, and the whole translation language bar opens the picker.
- **Steadier timeline cards.** Reminder, attachment and urgent marks share the preview space on ordinary collapsed cards, while captions and expanded notes keep their room.
- **Optional assistant Memory.** Keep a short introduction behind a separate opt-in, with your existing text preserved. Assistant, smart-summary and Memory settings dim when AI is off.
- **One place for AI request history.** What left this device stays under Security and privacy.
- **More selective note summaries.** Long explanations are condensed instead of merely reformatted, while short or information-dense notes keep the room their facts need.
- **Reliable quick capture.** Notification shortcuts open the right capture tool even when the timeline widget is active.
- **Safer photo editing.** Clearing all drawings and text now asks for confirmation before removing your work.
- **Control over assistant reads.** Reading Recently Deleted or recurring items for an answer waits for your approval.
- **Clearer selected filters.** Selected tag labels remain readable in light, dark and Comfort themes, including custom accents.

## v2.6.0

- **Easier photo cropping.** Larger touch areas make all four crop handles easier to drag while keeping the visible crop controls in place.
- **A clearer assistant history.** Conversations are grouped by time with reply previews and a current-chat indicator. Individual deletion is in each conversation’s menu.
- **A steadier pull to refresh.** Reversing your drag closes the refresh strip before the notes scroll. A quiet Nex accent marks success, with separate handling for cancelled and failed refreshes.
- **Find notes without tags.** Untagged stays at the end of the tag row and works with note-type and reminder filters.
- **More room to write.** The capture clipboard fades away once you start writing and gives its space back to the editor; clearing the text brings it back.
- **Clearer recurring cards.** Countdown and exact time sit together, with balanced spacing and centred actions. The check button explicitly marks one occurrence done.
- **Captions for text notes.** Add a separate optional caption without replacing the note on its timeline card. Captions are included in search and AI context.
- **Mark what is urgent.** Use More Actions or the hold menu to add a small flame. Urgency is independent of Pin and keeps notes in their existing order.
- **Daily nudges without AI.** Get brief local reminders based on urgent notes, nearby or recently overdue reminders, unfinished checklists and recurring items. A fresh smart summary is optional; otherwise Nex uses local text, with varied prompts for quiet and empty libraries and at most one daily notification.

## v2.5.4

- **Clearer note summaries.** More compact summaries better preserve decisions, conditions and figures, with readable formatting and a full expanded view.
- **Safer backup restore.** Backups made with an unsupported database format are refused before replacing your library.
- **Markdown that comes back cleanly.** Re-imported Nex text and checklist exports keep their dates, tags and titles, without metadata or file IDs appearing as note text.
- **Assistant controls that apply throughout.** Image and voice settings also govern media sent from the assistant, including changes made while a chat is open.
- **Less work while you type.** Short searches stay local; meaning searches wait for a typing pause and cancel superseded requests. Unrelated settings changes no longer rebuild the app's themes.

## v2.5.3

- **A visible summary timestamp.** The home summary shows how long ago its last successful AI update was, with minutes and hours and an exact time in its tooltip.
- **Relevant habit settings.** The habit-sharing option appears only while Habits is active.
- **Portrait rewrites stay visible.** Keep reading the current portrait while its replacement is written; the new text and traits appear on the same page.
- **Useful pinned modules.** Compact home cards show local progress, review counts, upcoming occasions, the selected breathing session or cycle information in place of large module names.

- **Still, a quieter theme.** Warm neutral surfaces and a soft sage accent, in light and dark. Cards, panels and menus have no decorative borders or shadows; focus and error states remain clear.
- **Clearer Markdown conversion.** “Convert to Markdown” distinguishes converting a note inside Nex from saving a file to your device.
- **Open PDF and DOCX with Nex.** Choose Nex from Android’s Open with menu to keep and read these documents, just like Markdown files.
- **Know when the next turn is.** Recurring cards show a countdown and the exact due date and time alongside daily progress, amounts and snooze status when relevant.

## v2.5.2

- **Readable wide tables.** Markdown and DOCX tables scroll horizontally with readable column widths, while surrounding text stays within the page.
- **Consistent notifications.** Opening Nex keeps module notifications in the notification centre. In-app messages use the top capsule throughout Nex, including Undo and retry actions.
- **Notes stay at the heart of your brief.** Preset summaries keep useful note content alongside optional habit progress. Full has room for more topics, and Plain report also includes recent notes without reminders.

## v2.5.1

- **Habits in your brief, by choice.** Opt in to include relevant habit goals, progress and short statistics in the home summary and daily notification. Switching it off hides previous habit content while keeping the notes summary and independent reminders.
- **Useful habit reminders.** See which habit is due, mark a tick done, open an amount's progress form, or ask for a reminder later.
- **Notifications open the right place.** Module notifications lead to their item or relevant section, including when Nex was closed, while respecting the app lock.
- **Consistent home AI.** Greetings follow the app language even after a failed request. Changing the brief's length or style applies on return from settings, without waiting for the hourly refresh.
- **Better AI editing.** Auto style corrects and organises writing. All six tools better preserve meaning and key details; Undo and Save remain under your control.
- **Clearer What's New.** Release history focuses on useful features and important fixes, with concise titles and clearer Persian.
- **A matching filter button.** When search is hidden, the filter button shares the tag pills' height and style.

## v2.5.0

- **More useful summaries.** Keep key decisions, dates, figures and next steps in summaries suited to the content.
- **Translation in more languages.** Choose from 36 searchable languages. Long translations show progress and resume unfinished parts while Nex stays open.
- **Comfortable reading.** Expand long text-file previews and tap inline code in assistant replies to copy it. Text-selection highlights and Persian notifications are clearer.
- **A calmer smart summary.** Its border animates once per expansion and fades smoothly, without restarting when you return from a note.
- **Clearer AI failures.** Image and audio tools explain known file, connection and service failures. Calendar days work individually with TalkBack.

## v2.4.1

- **Habit tracking.** Plan flexible schedules, track progress and streaks, and set reminders that respect completed and resting days.

## v2.4.0

- **New personal tools.** Birthdays & occasions, Word by Word and breathing exercises join the module catalogue.

## v2.3.6

- **Close long notes easily.** The note handle stays within reach while reading long content.

## v2.3.4

- **Tidier note tools.** AI actions and bank-card menus are clearer; Scheduled has one home in the Library.

## v2.3.3

- **A clearer archive.** Archived notes open read-only, remember hidden AI results and offer easier actions.

## v2.3.2

- **Scheduled in the Library.** Find upcoming notes in their own section and navigate back from archive and trash more reliably.

## v2.3.1

- **Act from notifications.** Mark recurring items Done, undo archive and trash actions, and find What's New in About.

## v2.3.0

- **Reminders and archive.** Handle reminders from notifications and manage archived notes, tags, threads and trash more easily.

## v2.2.2

- **A livelier writing portrait.** The portrait appears smoothly as you scroll and offers more varied suggestions when generated again.

## v2.2.1

- **A faster large library.** Return to deeply scrolled timelines more smoothly; Nex no longer duplicates itself in recent apps after updating.

## v2.2.0

- **Set notes aside.** Hide notes from the home timeline without deleting them; reminder navigation and bank-card editing are more reliable.

## v2.1.15

- **Consistent menus.** Tags, threads and tools share one familiar menu appearance.

## v2.1.14

- **Shorter forms.** Module forms ask for essentials first, fit above the keyboard and follow your calendar.

## v2.1.13

- **Occasions and habit calendars.** Keep important dates and review or update habits on a monthly calendar.

## v2.1.12

- **More useful modules.** Track quitting progress, see loan totals by currency and understand price comparisons more clearly.

## v2.1.11

- **Habit and loan reminders.** Set daily habit reminders and due-date loan reminders, and copy price comparisons.

## v2.1.10

- **Visible video results.** Completed YouTube analysis results now appear correctly.

## v2.1.9

- **Persistent reminders.** Reminders stay visible until handled; video-analysis failures and limits are explained more clearly.

## v2.1.8

- **Know your AI provider.** Test its abilities, choose a listed model and see why a feature is unavailable.

## v2.1.7

- **Your writing portrait.** Get a personal reflection from your notes, analyse YouTube links and read compact cards more comfortably.

## v2.1.6

- **Better PDFs and playback.** Swipe PDF pages, tap videos to pause and restore desktop backups without losing phone preferences.

## v2.1.5

- **Smarter summary refresh.** Automatic summaries wait for relevant changes and at least an hour; PDF pages stay visible while the next loads.

## v2.1.4

- **PDFs and videos in notes.** Read PDFs, play videos with controls and add attachments to link notes.

## v2.1.3

- **Safer editing.** Incomplete AI replies keep the original text; large-text layouts and module drafts are more reliable.

## v2.1.2

- **Reliable AI retries.** Stop or retry assistant requests, keep complete original text and avoid stale translation-language results.

## v2.1.1

- **A steadier editor.** Changing editor size preserves text and Undo; restore backups without restarting and test providers before saving.

## v2.1.0

- **Better AI and backups.** Use separate supported AI models, restore complete backups and read more reminder text in notifications.

## v2.0.10

- **Voice through custom providers.** Transcribe voice using compatible custom AI gateways.

## v2.0.9

- **Smoother card changes.** Deleting, restoring, pinning and filtering notes have clearer, gentler feedback.

## v2.0.8

- **Clearer focus and waiting.** Search and assistant fields show focus smoothly, with clearer feedback while a reply loads.

## v2.0.7

- **Tidier AI results.** Compact tools and result tabs sit below notes; hide results without hiding the tools.

## v2.0.6

- **Choose caption changes.** Choose whether AI text replaces a caption or is added to it.

## v2.0.5

- **Lighter everyday use.** Scrolling and editing are lighter, with clearer labels for image and audio actions.

## v2.0.4

- **Useful image reading.** AI describes images and organises extracted text; add the result to a caption by choice.

## v2.0.3

- **Capture selected text.** Save text from other apps, edit attached images and search the compact module catalogue.

## v2.0.2

- **Better editing and glass.** Formatting preserves line breaks, editing scrolls faster and glass styling reaches more screens.

## v2.0.1

- **Modules to try.** Add optional personal tools and enjoy more consistent panels and menus.

## v2.0.0

- **Faster capture.** Paste without keyboard flicker, save photos directly and optionally enable Liquid Glass.

## v1.99.99

- **Capture and reminder polish.** Paste from the capture box, recognise repeat-reminder times and dismiss selection by tapping elsewhere.

## v1.99.98

- **A cleaner capture box.** Capture tools share one outline, and web addresses work as soon as you write them.

## v1.99.97

- **Capture in one place.** Switch between note, checklist, link and voice in one composer; flick + for shortcuts.

## v1.99.96

- **Ask about Nex.** The assistant explains Nex features; app locking and photo editing are more reliable.

## v1.99.95

- **A calmer timeline.** Collapsed summaries stay closed, reminder indicators fit better and unplayable audio explains the problem.

## v1.99.94

- **Audio opens again.** Opening voice notes and audio files works reliably again.

## v1.99.93

- **A shared audio player.** Recordings and attached audio share one player, and search is easier to dismiss.

## v1.99.92

- **Pin tools to home.** Pin favourite tools, reuse recent searches and see when a checklist is complete.

## v1.99.91

- **Reliable search and saving.** Meaning search works again; device exports and voice playback are more reliable.

## v1.99.90

- **Richer attachments.** Browse note photos together, attach voice clips and manage files with a hold.

## v1.99.82

- **Relevant meaning search.** Meaning search shows related notes instead of repeatedly returning unrelated results.

## v1.99.81

- **Better search order.** Exact word matches appear before meaning-based suggestions.

## v1.99.80

- **Share several files.** Import files together, reorder attachments and search text from attached photos.

## v1.99.70

- **More attachments.** Attach several files to one note and select multiple gallery photos together.

## v1.99.60

- **Only the tools you need.** Optional modules have their own catalogue, with Cycle as the first available module.

## v1.99.50

- **Notes open faster.** Details open with content ready, and folding days is smoother.

## v1.99.40

- **A clearer first run.** Preview your greeting and choose note types and appearance more easily.

## v1.99.30

- **Tidier personal tools.** Library, private tools and settings are easier to browse; sharing and receipts are more reliable.

## v1.99.20

- **Preview your appearance.** Choose themes visually, customise your profile and set gestures more easily.

## v1.99.10

- **Better personal tracking.** Voice input stays in the assistant composer; automatic backups and interactive Cycle controls improve.

## v1.99.9

- **Talk to the assistant.** Use voice with supported providers and attach media to private saved messages.

## v1.99.8

- **Faster, steadier use.** Search and long timelines are quicker, release notes support Persian and drafts recover more reliably.

## v1.99.7

- **More reliable private data.** Cycle stays hidden when locked, period dates cannot overlap and shared media keeps captions.

## v1.99.6

- **Cycle answers on your phone.** The local assistant answers period questions without sending that context to a cloud provider.

## v1.99.5

- **Better local conversations.** The on-device assistant handles more notes and longer conversations reliably.

## v1.99.4

- **A steadier local assistant.** Local startup is more reliable, and an unstable model is no longer offered.

## v1.99.3

- **Meaning search on your phone.** Find related notes using an on-device search model.

## v1.99.2

- **A more current summary.** The smart summary reads fresh notes and offers fuller results when requested.

## v1.99.1

- **Reliable model downloads.** Model downloads continue in the background and manual summary refresh works consistently.

## v1.99.0

- **Cycle widgets.** Add a Cycle widget or its discreet version; sheets close more easily with a downward swipe.

## v1.98.0

- **A more personal Cycle.** Track fertility signs, enable a gentle companion and receive guidance after your pregnancy due date.

## v1.97.0

- **Cycle for different stages.** Choose a Cycle mode suited to your circumstances or turn it off completely.

## v1.96.0

- **Cycle tracking.** Track your menstrual cycle on a dedicated profile page.

## v1.95.0

- **Schedule a note.** Choose when a note appears on the timeline; selecting several notes is smoother.

## v1.94.0

- **Save to your device.** Save notes and media where you choose, rename files and write in full screen.

## v1.93.5

- **Better problem reports.** Optionally attach diagnostics when sending feedback.

## v1.93.4

- **Better private tools.** Import passwords reliably, keep bank-card CVV2 and clear a private tool when needed.

## v1.93.3

- **Clearer calendar choices.** Language and calendar settings present their choices more clearly.

## v1.93.2

- **Clearer settings and copying.** Browse reorganised settings, copy line breaks and recognise tags by distinct colours.

## v1.93.1

- **Fewer permissions.** Nex no longer requests Android's media-location permission.

## v1.93.0

- **More useful reading.** Copy replies and text-file contents, read formatted captions and scroll the summary widget.

## v1.92.3

- **Smoother writing and photos.** Typing and photo capture are smoother on slower phones.

## v1.92.2

- **Better Persian search.** Search recognises Persian and Arabic letter variants; exports include reminders, recurring items and threads.

## v1.92.1

- **Visible theme details.** Theme backgrounds display correctly and the home announcement keeps its intended size.

## v1.92.0

- **A more capable assistant.** Work with more notes and settings; copying a photo prioritises your caption.

## v1.91.1

- **Smoother editing.** Opening and scrolling the editor is smooth again, preserving normal touch behaviour.

## v1.91.0

- **Comfortable bilingual writing.** Persian and English lines retain direction while editing; addresses and amounts remain left to right.

## v1.90.1

- **Reliable backups and downloads.** Phone backups work again, downloads continue outside Nex and recovery codes copy in one tap.

## v1.90.0

- **Select several notes.** Act on multiple notes, choose card sizes and explore a fuller Recurring page and new themes.

## v1.89.0

- **Measure Nex on your phone.** Optionally view speed measurements and include them with feedback.

## v1.87.0

- **Recover without a server.** Create encrypted recovery backups, with better screen-reader and large-text support.

## v1.86.0

- **Safer taps and translation.** A tap closes open card menus; bilingual translations retain line direction.

## v1.85.0

- **See what was sent.** Review AI activity to see what left your phone.

## v1.84.0

- **Nex's own camera.** Capture photos in a camera panel over the timeline without leaving Nex.

## v1.83.0

- **A new look.** New opening animation and selectable app icons refresh Nex's appearance.

## v1.82.0

- **Find the best match.** Search ranks stronger matches first and combines word and meaning results more usefully.

## v1.81.0

- **Know an answer's source.** Replies cite notes; threads, Quick Settings capture and a Recurring calendar improve organisation.

## v1.80.2

- **Reliable incoming shares.** Shared content survives busy saves; tapping an open note menu only closes it.

## v1.80.1

- **Customise the hold menu.** Choose long-press actions and close menus without triggering another action.

## v1.80.0

- **Faster private tools.** Unlock private tools together, convert documents into notes and swipe editors closed.

## v1.70.0

- **Flexible recurring plans.** Use calendar schedules, browse upcoming and overdue items and keep private saved messages.

## v1.60.0

- **A private local vault.** Protect passwords and bank details with device authentication and optional encrypted backup.

## v1.50.0

- **Keep unfinished work.** Resume more drafts, create complete backups and convert notes to Markdown and back.

## v1.40.0

- **Safer capture and restore.** Sharing and restoring are more reliable; editors warn before discarding unsaved work.

## v1.30.0

- **Edit saved photos.** Crop and edit library photos, with clearer note-detail actions.

## v1.22.2

- **Better photo viewing.** Previews retain proportions and full-screen photo gestures respond reliably.

## v1.22.1

- **More flexible search.** Find text inside words; photos and profile details are kept more reliably.

## v1.22.0

- **Lighter Liquid Glass.** Glass controls are clearer, with calmer bottom navigation.

## v1.21.1

- **Safer restoration.** Failed restores keep existing notes; text alignment and note order are more reliable.

## v1.21.0

- **Useful text selection.** Selection menus focus on Nex actions; links and code remain tappable.

## v1.20.1

- **Smoother Persian selection.** Selection handles and dragging work more naturally in Persian notes.

## v1.20.0

- **Select what you read.** Select and copy notes, captions and replies, with steadier editor selection.

## v1.19.0

- **Clearer brief settings.** Daily brief settings have a page of their own; dismissing the keyboard is easier.

## v1.18.0

- **Read Word with the assistant.** The assistant reads Word documents; photo zoom and brief-settings scrolling are more reliable.

## v1.17.0

- **Ask about photos and files.** The assistant reads a focused note's image or text file; photos support zoom.

## v1.16.0

- **Make the brief yours.** Choose content, tone and length, including a plain offline report.

## v1.15.0

- **Filter by several tags.** Combine tag filters, open Recurring on its own page and read welcome controls easily.

## v1.14.0

- **Navigation within reach.** Bottom navigation brings common destinations closer; summaries and replies feel more natural.

## v1.13.0

- **Clearer AI availability.** Turning AI off takes effect immediately; widgets open the timeline as expected.

## v1.12.0

- **Capture without waiting.** Saving no longer waits for AI; recurring reminders and bilingual editing are more reliable.

## v1.11.0

- **Recurring commitments.** Keep recurring tasks separately, choose schedules and manage them with the assistant.

## v1.10.0

- **A smart-summary widget.** Read your brief in its own widget; the assistant handles more actions and settings.

## v1.9.0

- **A fuller editor.** Write with more room and ask AI to correct, restyle, shorten or simplify text.

## v1.8.1

- **Better widgets and privacy.** Select several widget tags; locking and screenshots behave more predictably.

## v1.8.0

- **Edit checklists.** Update checklist contents and read two lines per note in the widget.

## v1.7.1

- **Control your widgets.** Choose content and size, with more reliable locking and notification-sound settings.

## v1.6.2

- **Simpler reminders.** Choose reminder times together and pick colours accurately.

## v1.6.1

- **A working timeline widget.** The home-screen timeline widget displays notes correctly.

## v1.6.0

- **Better recap and recovery.** The recap recognises notes; undoing deletion restores their original place.

## v1.5.5

- **Your timeline on home.** Use a timeline widget that respects app locking, with smoother shares and update downloads.

## v1.5.4

- **Private while locked.** Notes stay hidden during authentication and in recent apps when locking is enabled.

## v1.5.3

- **Safer large attachments.** Handle large files without freezing Nex, with a clear 100 MB attachment limit.

## v1.5.2

- **More reliable drafts.** Fast typing avoids extra drafts; large-file sharing is smoother and reminders respect lock-screen privacy.

## v1.5.1

- **Reliable reminder controls.** Cancelling the clock creates no reminder; video previews and scrolling are lighter.

## v1.5.0

- **Reminders while writing.** Set reminders during capture, filter upcoming reminders and recognise shared videos by their preview.

## v1.4.0

- **Read files in notes.** Preview text and Word, play audio, format text and resume interrupted update downloads.

## v1.3.2

- **Predictable gestures.** A tap closes swiped-open cards and swipe-back transitions are steadier.

## v1.3.1

- **Launch restored.** Fixes the issue that prevented the previous version from opening.

## v1.3.0

- **Reliable deletion and reminders.** Permanent deletion removes notes and their reminders; search filters and restore are more dependable.

## v1.2.7

- **Start writing immediately.** Fresh installs are ready for capture; the assistant no longer claims unfinished actions succeeded.

## v1.2.6

- **Clearer failures.** Microphone and search failures explain what happened and offer retry where available.

## v1.2.5

- **Steadier glass and writing.** Glass stays readable; mixed Persian-English text keeps its direction while typing.

## v1.2.2

- **Optional glass and app lock.** Choose Liquid Glass, complete your profile and protect Nex with device authentication.

## v1.2.1

- **Reminder settings restored.** Reminder and daily-nudge controls work correctly in installed release builds.

## v1.2.0

- **More reliable notifications.** Notification permission and reminder setup are more reliable.

## v1.1.0

- **Clearer assistant replies.** Internal commands stay out of replies; note details grow naturally with their content.

## v1.0.0

- **Repeat and organise.** Set repeating reminders, manage storage and jump from a reminder to its note.

## v0.9.9

- **Reliable reminders.** Reminder delivery and bilingual writing are more reliable.

## v0.9.8

- **More swipe actions.** Choose more card actions, preview Markdown and read formatted assistant replies.

## v0.9.7

- **Days and daily reminders.** Fold date groups, import Keep photos and choose a daily notification time.

## v0.9.6

- **An assistant on your phone.** Download a local model with pause and resume; copy assistant messages with a hold.

## v0.9.5

- **Import and translate.** Import Keep notes, translate text and ask the assistant by voice.

## v0.9.4

- **Reminders and chat history.** Set reminders, keep conversations and back up attached photos, audio and files.

## v0.9.3

- **A more natural assistant.** Hold capture to open the assistant and read better Persian replies and summaries.

## v0.9.2

- **Checklists and links.** Create lists and link notes, with an introduction and personalised greeting.

## v0.9.1

- **Personalise and capture.** Adjust size and colour, edit photos, search by meaning and send feedback.
