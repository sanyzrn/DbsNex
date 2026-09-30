# Using Nex

Nex is the fastest way to put something down and find it again: a thought, a photo, a recording, a file or a link, all in one stream. Everything stays on this phone unless you choose otherwise, and the library works completely without AI.

## Capture something

Tap **+** at the centre of the bottom bar and choose text, checklist, voice, photo, file or link. There is no Save button for quick text: it is saved when you close its sheet. Checklists, links and other editors have a **Save** or **Confirm** button. A checklist uses one item per line; a link needs a complete address.

Without opening Nex first: add the **Nex capture** tile to your Quick Settings (pull the shade down twice, then edit the tiles), or turn on **Settings → Capture → Capture from notifications** for a silent row with **Note**, **Voice** and **Photo** buttons.

Photos first open in a full-size preview. Choose **Edit** only when you want to crop, rotate or annotate; swipe the aspect-ratio row to see every size. Files shared into Nex from another app arrive exactly like files you pick inside it.

![The capture menu](capture.webp)

## The home timeline

Everything lives in one reverse-chronological stream, grouped under date headings. Tap a heading to fold its day; pinch two fingers together on the timeline to fold every day at once, and spread them to open them all again.

Hold a note for a quick menu: **Pin**, **Copy**, **Edit**, **Remind** and **Delete** by default. **Settings → Capture → Hold menu** can add any action from a note's details — Share, Add tag, Translate and the rest — or take some away. Up to five notes can be pinned to the top. Swipe a card from either edge for the actions you chose under **Settings → Capture → Swipe actions**. The bottom bar holds, from left to right: **Tools**, **Recurring**, **+**, **Library** and **Settings**.

![The home timeline](home.webp)

## Find and organize

Tap anywhere in the search field and type part of a word: **tor** also finds **Generator**. The chips beside the field narrow results by type, tag or date, and `tag:` and `type:` still work in the field itself. When nothing matches, Nex offers the closest thing you actually wrote.

**Threads** gather notes about the same thing — a renovation, a trip, a project — without moving them: a note in a thread is still on the timeline and under its tags, and can be in several threads or none. When a note you have just saved clearly continues one, a capsule offers to add it; nothing is added without a tap, and **Settings → Capture** turns the offer off. Find them in **Library → Threads**, where a thread reads oldest first, and from a note's details, where its threads sit beside its tags.

Tags group related notes and can carry any colour. **Library → Tags** renames, merges and deletes them; **Library → Trash** keeps deleted notes for 30 days, so a mistake can be undone.

![Search with filters](search.webp)

## Read, edit and share

Open an item for its exact date and time, tags, description and every action. The common actions are always visible; **More** holds the rest. Select text to copy or format it. Open a photo to zoom with two fingers, drag to look around, and drag down to close it.

Voice notes show playback, a position slider and a waveform drawn from the recording itself on Android. Formats without a waveform still play.

![A note's details](note-details.webp)

## Long notes, Markdown and files

Long notes open folded; tap **More** to read the rest and **Less** to fold them again.

A text note can become a Markdown file with **Save as Markdown**: the same item, with its tags, pin and reminder, now a `.md` file you can share. That is the only direction a note is ever converted — Markdown is what a note already is.

The other way round works for any file that is mostly words. Open a file item and tap **Convert to note** to turn it into editable, searchable text. This works for Markdown, plain text and logs, Word (`.docx` and older `.doc`), OpenDocument (`.odt`), Rich Text (`.rtf`), web pages (`.html`), e-books (`.epub`), spreadsheets saved as `.csv` or `.tsv` (they become a table), and source or configuration files (they keep a fixed-width font). Older Persian text files in Windows encoding are read correctly. PDFs stay files: their text has no reliable reading order. Files up to 16 MB are supported, and a failed conversion leaves the original untouched.

![Turning a file into a note](files-to-notes.webp)

## Recover unfinished work

If Android closes Nex while you are editing, reopen the same editor to find its draft waiting: note text, captions, checklists, links, profile details and recurring items are all kept. To resume an unfinished photo, choose Photo again; crop and annotation drafts reopen from their own editors. Discarding a draft on purpose removes it, and quick text is recovered automatically at startup.

## Reminders

A reminder brings one note back at the time you choose, once or repeating. Use the quick choices, the wheels or the calendar button, and confirm the time shown. Android's notification permission is required. If Android refuses to schedule one — exact alarms off, notifications blocked, battery optimisation — Nex tells you in Android's own words, and **Settings → Notifications** has a test notification to tell "Nex never sent it" apart from "the phone swallowed it".

## Recurring

**Recurring**, on the bottom bar, is for the things that come back round: rent, insurance, a tablet every eight hours, a glass of water every two. They are not notes and never crowd the timeline.

Tap **+** on the Recurring page to add one: a title, how often, and when it is next due; optionally how far ahead to be told, a daily window for hourly items, several weekdays, a day of the month or its last day, and an amount with its currency. Persian monthly and yearly repeats follow the Persian calendar. Swipe the editor down from anywhere on it to close it; it asks first if you have typed something.

Today, Overdue and Next 7 days narrow the list; **Calendar** shows a month or a week, each day shaded by how much falls on it, and what is due on the day you tap. The next occurrence can be moved from there without moving the schedule. In an item's editor, **Attachments** holds receipt photos, links to any note and, optionally, one bank card from the vault, which only opens after the vault is unlocked and is never shown to the assistant. Mark an item done to move it to its next turn; its menu can snooze one occurrence, skip it or open its history, where each entry can carry a short note. Undo restores an accidental change, and snoozing never moves the underlying schedule. Upcoming 30-day totals are shown per currency.

![The Recurring page](recurring.webp)

## The assistant and AI

AI is optional and off until you turn it on. In **Settings → Intelligence**, choose a provider (or a downloaded offline model) — for **Custom**, enter the full chat address, which is used exactly as written — test it, and pick which features to use: transcription, text in photos, summaries, tag suggestions, related notes and the daily smart summary.

**Hold +** to open the assistant: a light washes across the screen and the panel grows out of the button. Ask about your notes, or ask it to act — create, edit, tag, remind, pin, merge, add a recurring item, or change a setting such as the theme palette, accent, text size or language. Nothing is applied until you confirm it. A cloud provider receives only what the request needs; an offline model keeps everything on the phone.

If your model thinks before it answers and the summary comes back empty, turn on **No token limit** in the Smart summary settings — it can use many more tokens, as the summary refreshes several times a day.

Tap the smart summary to open or fold it and pull down to refresh it. Hold the greeting for another phrase.

When an answer uses your notes, they appear under it as chips; tap one to open that note. With **Stay in my notes** off, an answer that comes from general knowledge instead says so.

![The assistant opening](assistant.webp)

## Tools and private vault

**Tools**, at the left of the bottom bar, holds **Passwords**, **Bank cards**, **Private saved messages** and a **Password generator**. The private tools need your fingerprint or screen lock, and one unlock opens all of them for as long as you are using them. They lock after two minutes without activity — including time spent in another app, so you can copy a password, paste it in your browser and come straight back. Leaving the app always hides their contents from the task switcher, and **Lock** closes them at once.

Everything is shown on the list itself: each password with its login, password, website and notes, and each card as a card with every detail underneath. Tap any field, or its copy icon, to copy it. Use the **⋮** menu on an item to edit it, favourite it or delete it. Each bank card can have its own colour, chosen with the same picker as tags. In Passwords, **Import Chrome CSV** adds passwords exported from Chrome, skipping exact duplicates; delete the exported file afterwards, as it is not encrypted.

The vault uses the phone's secure storage and never enters notes, widgets, search or AI. Unfinished edits are kept as encrypted drafts. Copied values are marked sensitive, and the clipboard is cleared after 30 seconds where Android allows it. The vault is included in a backup only when you choose **Include private vault** in a complete backup.

![Tools](tools.webp)

![Bank cards with every detail on the list](vault-cards.webp)

## Appearance, language and calendar

**Settings → Appearance → Theme** sets, in order: light, dark or system mode; text size; the accent colour; and the whole-app palette — Nex, Paper notebook, Autumn, Rose atelier or Forest retreat. Choosing a palette also brings its own accent, and the accent row shows the colour actually in use; pick another accent afterwards if you prefer.

At the end of the Theme page, **App icon** changes the icon on your home screen to one of six; a home-screen shortcut may need adding again afterwards.

Language, calendar and the home-screen widget are also under Appearance. The field at the top of Settings finds any setting by name, or by something on the page it opens — "accent" finds Theme. The Persian calendar changes how dates are shown and picked, independently of the interface language; what is stored never changes. Settings remembers which categories you opened; Security, Intelligence and Appearance start open.

![The Theme page](theme.webp)

## Notices inside the app

Confirmations and warnings arrive as a small capsule that drips down from the top of the screen and is drawn back up when it leaves. Tap it or swipe it upwards to dismiss it early. When it offers **Undo**, it stays a little longer so there is time to reach it.

![A notice with Undo](notices.webp)

## Home-screen widgets

Add the **Capture**, **Timeline** or **Recap** widget from your launcher. Under **Settings → Appearance → Home screen widget**, choose which kinds of note and which tag the timeline widget shows and whether pinned notes come first. Widgets follow the app's language and accent. While the app lock is closed they hide your notes, unless you choose otherwise.

![Home-screen widgets](widgets.webp)

## Backups and restoring

**Settings → Data & backup** offers three separate things:

- **Export / Import** moves library content in and out. Importing adds to the current library, including exports from Google Keep and Takeout.
- **Library backup / Restore** keeps or replaces the whole library with its attachments. Automatic local copies stay on this phone; share a copy somewhere else to survive losing the phone.
- **Complete backup** adds settings and service keys, the private vault if you choose it, and optionally the downloaded offline model (about 2.6 GB). Settings, keys and vault are encrypted with a generated recovery code — keep it separately, because it cannot be recovered from the backup.

Restoring replaces the library and restarts Nex. If a restore is interrupted, the next launch puts everything back as it was.

![Data and backup](backup.webp)

## Security and privacy

Under **Settings → Security**, Nex can ask for your fingerprint or screen lock whenever it returns to the foreground, after a delay you choose. The lock is local and hides the screen in the task switcher. Nothing leaves the phone unless you turn on a cloud AI provider, send feedback or share something yourself.

## Updates, feedback and help

**Settings → About Nex** shows the installed version and checks for updates; releases download inside the app and install over the existing one, keeping all your data. The same page links to the maker, **DbsStudio.ir**, and to Nex's own page with news, downloads and help.

**Send feedback** goes straight to the people who make Nex. Choose whether it is a problem, an idea or something else, and add a Telegram ID or email if you would like a reply; nothing from your notes is attached. If sending is not available, copy your message and send it another way. If something fails, **Share diagnostics** creates a report with personal details removed.
