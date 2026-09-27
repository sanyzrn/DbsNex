# Using Nex

Save a thought, photo, recording or file in one place. You can use the library without enabling AI.

## Capture something

Tap **+** and choose text, checklist, voice, photo, file or link. Quick text is saved when you close its sheet. Other editors have a **Save** or **Confirm** button. A checklist uses one item per line. A link needs a complete address.

Photos first open in a full-image preview. Choose **Edit** only when you want to crop, rotate or annotate. Swipe the aspect-ratio row to see every size. You can also edit an existing image from its details.

## Find and organize

Tap anywhere in the search box and type part of a word: **tor** also finds **Generator**. Filters narrow results by type or tag. The smart summary stays out of search.

Use tags to group related notes. Pin important notes to keep them at the top. A date heading folds its group; pinch two fingers together on the timeline to fold all date groups, or spread them to open all groups. Individual group controls remain available without gestures.

## Read, edit and share

Open an item for its exact date and time, tags, description and actions. The most common actions are visible; **More** holds the rest. Select text to copy or format it. Open a photo to zoom with two fingers, then drag to inspect it. Drag down to close the photo.

Voice details offer playback, a position slider and a waveform derived from the recording on Android. Unsupported audio still uses the player without a waveform.

## Long notes and Markdown

In a text note's actions, choose **Save as Markdown**. Nex replaces the item's representation with a `.md` file and preserves its identity, tags and reminders. You can share the file with another app. For a Markdown attachment, **Convert to note** restores editable text. Imported Markdown must be UTF-8 and no larger than 16 MB. A failed conversion leaves the original intact.

## Recover unfinished work

If Android closes Nex while you are editing, reopen the same editor to recover its saved draft. This includes note text, captions, checklists, links, profile details and commitments. To resume an unfinished photo capture, choose Photo again; crop and annotation drafts reopen from their editors. Explicitly discarding a draft removes it. Quick text has automatic startup recovery.

## Reminders and commitments

A note reminder brings one item back at a chosen time. Use the quick choices, wheels or calendar button, and confirm the time shown. Android notification permission is required.

Open **Commitments** from the bottom navigation for recurring obligations such as rent or medication. Give it a title, interval and next due time; optionally set advance notice and a daily window. Mark it done to advance its schedule.

## AI and the smart summary

In **Settings → Intelligence**, configure a provider or an available offline model, adjust the assistant, then choose how the smart summary works. Cloud providers receive the content needed for the requested action; offline processing stays on the device. An API key and a working connection are needed for cloud features.

Tap the summary to expand or fold it; pull down to refresh it. Hold the greeting to request another phrase. The greeting also works without a profile name. Review the assistant's proposed changes before applying them.

## Appearance, language and calendar

Settings uses expandable categories. Under **Appearance**, choose theme, accent, background, glass, text size, language and calendar. The Persian calendar controls displayed dates and date selection independently of the interface language. Stored instants stay unchanged. Choose Gregorian to switch back.

Under **Capture**, configure Enter, haptics and swipe actions. Under **Notifications**, choose the daily nudge and open Android's sound settings. Under **Security**, configure app lock and its timing. Widget privacy follows the app lock.

## Backups and restoring

**Settings → Data and backup** offers three different operations:

- **Export / Import:** transfer library content. Import adds content to the current library.
- **Library backup / Restore:** keep or replace the library, including its attachments. Local automatic copies live on the same device; export a copy somewhere else for protection against losing the device.
- **Complete device backup:** include settings and service keys, plus an optional downloaded offline model. Settings and keys are encrypted with a generated recovery code. Save the code separately: it cannot be recovered from the backup. Library files and model weights are not encrypted. The model can add about 2.6 GB.

Restoring a backup replaces the library and restarts Nex. Device identity and installation-specific file paths stay local. Keep the old backup until you have checked the restored contents.

## Updates and help

Open **Settings → About** for the installed version, update check and changelog. App releases come from **DbsNex-releases**. Install updates over the existing app to retain its data.

If something fails, record the app version, what you tried and the error shown. Diagnostic export can help investigation. Feedback delivery depends on the service being configured; an unavailable service does not mean your message was received.

## Tools and private vault

Open **Settings → Tools**, then Passwords or Bank cards. Device authentication
is required. Save account names, logins, passwords, websites and private notes;
the generator offers password length and symbol controls. Cards have bank,
holder, number, printed expiry, IBAN and account fields. Tap a field or its copy
icon to copy it. Passwords and card numbers stay masked until revealed.

The vault uses device secure storage and does not enter notes, widgets, general
search or AI context. It locks when the app loses focus or after two idle minutes.
Unfinished edits are encrypted drafts that can be resumed after unlocking.
Android marks copied values sensitive; clipboard expiry after 30 seconds is best
effort and depends on OS access. Autofill and vault sync are not included yet.

For transfer, explicitly select **Include private vault** in Complete app backup
and authenticate. The vault is inside its encrypted settings entry. Keep the
recovery code separately. Ordinary note/library backups do not include it.
