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

Long note details initially show a short preview; tap **More** to read the rest and **Less** to fold it. Hold a home item for Pin, Copy, Edit, Remind and Delete.

In a text note's actions, choose **Save as Markdown**. Nex replaces the item's representation with a `.md` file and preserves its identity, tags and reminders. You can share the file with another app. For a Markdown attachment, **Convert to note** restores editable text. Imported Markdown must be UTF-8 and no larger than 16 MB. A failed conversion leaves the original intact.

## Recover unfinished work

If Android closes Nex while you are editing, reopen the same editor to recover its saved draft. This includes note text, captions, checklists, links, profile details and commitments. To resume an unfinished photo capture, choose Photo again; crop and annotation drafts reopen from their editors. Explicitly discarding a draft removes it. Quick text has automatic startup recovery.

## Reminders and commitments

A note reminder brings one item back at a chosen time. Use the quick choices, wheels or calendar button, and confirm the time shown. Android notification permission is required.

Open **Recurring** from the bottom navigation for recurring obligations such as rent or medication. Give it a title, interval and next due time; optionally set advance notice and a daily window. Mark it done to advance its schedule.

Recurring has Today, Overdue and Next 7 days filters. Use a template for a subscription, installment, task or habit. Its menu can snooze one occurrence, skip it or open history; Undo restores an accidental completion or change. History entries accept a short note. Choose weekdays, a month day or the last day of the month. Persian recurrence calculates monthly/yearly dates using the Persian calendar. An optional amount and currency contribute to upcoming 30-day totals, with each currency kept separate. Snoozing preserves the original schedule.

## AI and the smart summary

Hold **+** to open the assistant. In **Settings → Intelligence**, configure a provider or an available offline model, adjust the assistant, then choose how the smart summary works. Cloud providers receive the content needed for the requested action; offline processing stays on the device. An API key and a working connection are needed for cloud features.

Tap the summary to expand or fold it; pull down to refresh it. Hold the greeting to request another phrase. The greeting also works without a profile name. Review the assistant's proposed changes before applying them.

## Appearance, language and calendar

Settings remembers which categories you open or close, including after restarting the app. Security, Intelligence and Appearance start open. Under **Appearance → Theme**, choose Nex (the classic look), Paper notebook, Autumn, Rose atelier or Forest retreat, light/dark/system mode, accent and text size. Language, calendar and home-screen widget settings remain under Appearance. Liquid Glass is temporarily unavailable. The Persian calendar controls displayed dates and date selection independently of the interface language. Stored instants stay unchanged. Choose Gregorian to switch back.

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

Tap **Tools** at the left of the bottom navigation, then Passwords or Bank cards. Device authentication
is required. Save account names, logins, passwords, websites and private notes;
the password generator is a separate tool with length and symbol controls. Cards have bank,
holder, number, printed expiry, IBAN and account fields. Tap a field or its copy
icon to copy it. After authentication, saved fields are readable immediately.

In Passwords, use **Import Chrome CSV** to select an exported UTF-8 CSV file. Review the number of new entries before confirming; identical website/login/password entries are skipped. The source CSV is not encrypted, so remove it safely after import.

**Private saved messages** is a separate authenticated text space: type, send to save, then copy or delete. Unsent message text is cleared when it locks. Swipe back to return from a tool or its details.

The vault uses device secure storage and does not enter notes, widgets, general
search or AI context. It locks when the app loses focus or after two idle minutes.
Unfinished edits are encrypted drafts that can be resumed after unlocking.
Android marks copied values sensitive; clipboard expiry after 30 seconds is best
effort and depends on OS access. Autofill and vault sync are not included yet.

For transfer, explicitly select **Include private vault** in Complete app backup
and authenticate. The vault is inside its encrypted settings entry. Keep the
recovery code separately. Ordinary note/library backups do not include it.
