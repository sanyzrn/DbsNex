# Nex — UI/UX audit (v1.30.0 / `702670e`)

**Date:** 2026-09-25 · **Build:** published v1.30.0 release on the Android 37 emulator (Pixel 10 Pro AVD, 427×952 dp, 480 dpi). Code is identical to HEAD `702670e` apart from a docs file.
**Compared against:** `docs/05-design.md` and `packages/ui/lib/tokens/nex_tokens.dart`.
**Workspace:** no source changed during the audit; only this report and its `ux/` screenshots folder were added to the root afterwards, on request. Screenshots are in `ux/` next to this file. `*_s.png` files are half-size; `cNN.png` files are side-by-side montages.

**Covered:** English and Persian (RTL); light and dark; Liquid Glass on/off; system font scale 1.0 and 2.0; a 360×640 dp small-phone emulation; the on-screen keyboard and a hardware keyboard; empty, error and offline states; home-screen widgets; swipe, double-tap, drag and draw gestures.
**Not covered:** onboarding (needs a fresh install, which would wipe data); a Windows runtime (the host can't build Windows — see §5); the Solar Hijri calendar option (none exists).

> **Caveat.** Someone else used the emulator during the session: the theme changed to Dark, the mic permission was granted, and a voice note was saved without my input. Findings below are limited to behaviour I reproduced or saw directly. AI-generated text is shown as the app renders it; I make no claim that it is correct.

---

## 1. Summary

The visual language is mostly coherent: clean type, consistent sheets, and good reduced-motion support. But four problems hit core tasks:

1. **Photo editing is fragile.** The crop and annotate screens close on a horizontal drawing stroke or an edge-handle drag, losing the edit. The editor also lays the photo out wider than the screen.
2. **The capture sheet moves its primary button** on the first keystroke, and another control lands exactly where Send was.
3. **Checklist and link capture drop what you typed** if you dismiss them. The text sheet does the opposite: it auto-saves.
4. **The pinned filter row has no background.** It floats over and collides with note text whenever the list scrolls.

Secondary themes:
- Accessibility gaps: sub-48 dp targets, unlabeled controls, an invisible switch track, card edges at ~1.1:1 contrast.
- Persian polish: Gregorian dates, mixed digit systems, English starter tags and type labels, colloquial or inconsistent terms.
- Several places where the shipped UI departs from `05-design.md`.

---

## 2. Confirmed defects (prioritised)

### UX-1 (High) — A horizontal stroke or edge drag closes the photo editor and loses the edit
**Screens:** `ux/29_crop_s.png`, `ux/31_annotate_s.png`
**Repro 1.** Photo note → Edit → Draw or add text. A vertical stroke draws normally. A **left-to-right stroke closes both the annotate and crop screens** and returns to the note, and the unsaved drawing is lost.
**Repro 2.** In Crop, drag the left handle. It sits at x≈0, so the drag becomes Android's back gesture and the editor closes.
**Cause.** Both routes are `NexPageRoute` with the full-width swipe-back left on (`note_detail_sheet.dart:305`, `photo_crop_screen.dart:150`, `photo_preview_screen.dart:77`). The full-screen viewer already opts out (`swipeBackEnabled: false`, `note_detail_sheet.dart:906, 2009`).
**Fix.** Set `swipeBackEnabled: false` on crop, annotate and preview. Inset the crop viewport from the system gesture zones (`MediaQuery.systemGestureInsets`). Confirm before discarding a dirty edit.

### UX-2 (High) — The crop editor lays the photo out wider than the screen
**Screen:** `ux/29_crop_s.png`
**What happens.** Both sides of the image are cut off (e.g. "earch notes…"), and the crop handles sit half off-screen. The ratio row (Free, 1:1 … 9:16) is **clipped at "9:16"** with no scroll cue. "Draw or add text" wraps to two lines.
**Cause.** `crop_your_image` sizes its viewport from `MediaQuery` rather than its own box — the screen's own comment near `_rotate` acknowledges this.
**Fix.** Constrain the `Crop` widget with a `LayoutBuilder` and fit the image to that box with padding. Make the ratio row scroll with an edge fade, or use a menu.

### UX-3 (High) — The capture Send button jumps, and Remind takes its place
**Screen:** `ux/c05.png`
**Repro.** Open Capture and type one character.
**What happens.** A Remind button is inserted into the action `Wrap`. Remind lands **exactly where Send was**, and Send drops to a new row at the far leading edge. Tapping where Send used to be opens the reminder picker. On a 360 dp phone, Send is on its own second row from the start (`ux/c21.png`).
**Cause.** `capture_sheet.dart:343-396` puts Send and Remind at the end of a single `Wrap(spacing: 2)`.
**Fix.** Pin Send in a fixed trailing slot outside the wrap (for example a `Row` with the type actions in an `Expanded` scroller). Reserve Remind's space from the start, or place it left of the field.

### UX-4 (High) — Checklist and link capture discard input on dismiss
**Screens:** `ux/c06.png`, `ux/c07.png`
**Repro.** Capture → Checklist → type "Milk", Enter, "Bread" → press Back. No note is created and there is no prompt. Link behaves the same.
**Why it matters.** README says "No Save button anywhere: every capture is committed the moment it exists". The text sheet auto-saves; these two sheets don't.
**Cause.** They return only from their buttons (`checklist_capture_sheet.dart:101-103, 174, 283, 315`).
**Fix.** Save on dismiss (as the text sheet does), or at least confirm.
**Also:** the counter says **"2 notes"** for two items, because it uses `l10n.noteCount` (`checklist_capture_sheet.dart:129`). Add an "items" plural.

### UX-5 (High) — The pinned filter row floats over the list with no background
**Screens:** `ux/c18.png`, `ux/c19.png` (Glass on, same problem)
**Repro.** Scroll the timeline a little. The "All"/"همه" chip and filter button stay pinned but transparent, colliding with card text and icons.
**Cause.** `_FilterRowHeader` paints `surface` only when `overlaps` is true (`timeline_screen.dart:3214-3240`). `overlapsContent` means *earlier slivers overlap this header*, not *content has scrolled under it*, so it never paints.
**Fix.** Paint when `shrinkOffset > 0` or when the scroll offset has passed the header, or always paint (glass or surface) with a fade.

### UX-6 (Medium) — The off-state switch track is invisible
**Screens:** `ux/z_glass_row.png` (light), `ux/z_glass_final.png` (dark)
**What happens.** The off-state track is invisible in both themes; only a grey thumb dot shows, so the row doesn't read as a toggle.
**Cause.** `nex_tokens.dart:725-732` sets `trackOutlineColor` transparent, the default off-track matches the settings-card fill, and `NexSwitch` scales the control to 0.8 (`nex_switch.dart:30-51`).
**Fix.** Give the off state a track that contrasts ≥3:1 with the card (WCAG 1.4.11), or keep the outline.

### UX-7 (Medium) — Touch targets under the 48 dp floor
| Control | Size | Where |
|---|---|---|
| Crop ratio chips | 62×40, "9:16" 45×40 | `photo_crop_screen.dart:190` |
| Annotate colour swatches | 34×34 | `photo_annotate_screen.dart:293-294` |
| Reminder quick chips | 40 tall | `reminder_wheel.dart:216` |
| Tag picker chips | 36 tall | `TagChip`, `note_card.dart:737` |
| Home-screen widget buttons (refresh, capture) | 34×34 | `widget_recap.xml:65-66`, `widget_timeline.xml:69-70` |

`docs/05-design.md` and `accessibility_test.dart` promise 48×48 dp. The test doesn't cover these surfaces.

### UX-8 (Medium) — Unlabeled controls for screen readers
- Voice **play** button: empty label (`ux/22_voice_detail_s.png`).
- Annotate colour swatches: no labels. The stroke slider is announced only as "22%".
- The photo in the detail sheet is an unlabeled image.
- Voice and photo cards announce just "voice" / "photo". Text cards say "Text note. …". No card announces a time.

The spec says every card announces type, preview, timestamp and tags.

### UX-9 (Medium) — Type filter state is contradictory
**Screen:** `ux/25_filter_photo_s.png`
Choosing Filters → Photo shows only photos, but the **"All" chip stays selected**. The only cue is a tinted filter icon; there's no "Photo" chip and no one-tap clear (spec: "always reversible with a single clear action"). The filter sheet also has no title.

### UX-10 (Medium) — The permission-denied banner hides the fix
**Screen:** `ux/21_camera_denied_s.png`
The text is truncated at "You can …", before it says how to grant access (`nex_banner.dart:290`, `maxLines: 2`; string at `app_en.arb:1216`). The action is "Try again", which Android suppresses after repeated denials.
**Fix.** Allow three lines or shorten the copy, and offer "Open settings" once the permission is permanently denied.

### UX-11 (Medium) — Photo detail preview crops the image
**Screen:** `ux/c10.png`
The preview uses `BoxFit.cover` at a fixed 220 px height (`note_detail_sheet.dart:910-915`). Annotations near the edges (e.g. text written at the top) are cut off in the preview.
**Fix.** Use `contain` with a letterbox, or cap the height by aspect ratio.

### UX-12 (Medium) — Bright pastel slabs in dark theme
**Screen:** `ux/44_assistant_settings_dark.png`
`primaryContainer` maps to `accentStrong` (`nex_tokens.dart:462, 513`), which is a light tint in dark mode. The assistant intro banner (`assistant_screen.dart:52-57`) becomes a bright peach block with dark text on a black screen. On the same screen, the footnote "Included with your messages…" escapes the card padding and touches its rounded edge (`assistant_settings.dart:154-163`).

### UX-13 (Medium) — AI text rendered without a guard on the most prominent surfaces
**Screens:** `ux/c01.png`, `ux/39_launcher_widgets_s.png`
With the configured free reasoning model, the greeting reads "The user wants a short greeting…, hites". The recap card and the Daily Digest home-screen widget show "We need to produce at most 4 lines…".
- The greeting sits directly above the search pill and is itself a tap target ("Tap for a new line"), so near-misses trigger new AI calls. I triggered two by accident.
- In the Persian UI the greeting is English.

This is the app displaying unfiltered model output; it is not a judgement of the model.

### UX-14 (Low/Medium) — Persian localisation gaps
- **Calendar:** Gregorian dates and month names ("یکشنبه ۲۷ سپتامبر") with no Solar Hijri option (`ux/93_reminder_s.png`).
- **Digits:** mixed. The reminder picker uses Persian digits (۱۲:۳۱); detail headers use Latin ("2026-09-25 07:01:54").
- **Untranslated strings:** media cards show the enum names "photo"/"voice" (`note_card.dart:415`); starter tags stay English ("Idea", "Work"… in `ux/c23.png`).
- **Terminology and register:** "نوت‌هایت" in the assistant versus "یادداشت" elsewhere. Cancel is the colloquial "بی‌خیال", and the capture hint is colloquial ("چی تو ذهنته؟"), while other copy is formal.
- **Bidi:** the file metadata line is scrambled ("KB · application/octet-stream 1.2", from the earlier audit, `note_detail_sheet.dart:966-973`).

### UX-15 (Low) — Voice note presentation
Cards show only the word "voice", with no duration or waveform (the spec requires "waveform + duration"). In the detail sheet, "Voice" appears twice, and the header says "42s" while the player says "00:41". Copy is a primary action on voice notes that answers "This note has no text to copy" (`ux/22_voice_detail_s.png`).

### UX-16 (Low) — Link sheet reads the clipboard on open
Opening Capture → Link triggers Android's "Nex pasted from your clipboard" notice even when nothing is inserted (`ux/c07.png`; `checklist_capture_sheet.dart:237`). Offer a Paste chip instead of reading automatically.

### UX-17 (Low) — Offline assistant error blames the configuration
**Screen:** `ux/94_assistant_offline_s.png`
In airplane mode the reply is "No reply came. Check the service in settings or try again." There's no offline detection and no retry button, so the message must be retyped. Two drag handles are stacked at the top of the sheet.

### UX-18 (Low) — Smaller inconsistencies
- The Add Tag swipe panel is tinted blue-grey, but the spec asks for a neutral surface (`ux/c22.png`).
- In the tag manager, a tag with no colour shows an **empty circle that reads as a radio button** (`ux/c12.png`).
- The Home layout entry uses the "grid +" icon (Android's "add widget" idiom).
- Home-screen widgets ignore the accent colour. The timeline widget's last row is cut off, and it labels "Photo"/"Voice" while in-app cards say "photo".
- Trash's empty state doesn't mention the 30-day retention.
- The same feature has **four names**: "Daily brief" (Settings), "Today's summary" (card), "Daily Digest" (widget), "Nex Recap" (widget picker).

---

## 3. Design improvements

- **Chrome versus content.** On a 360×640 dp phone, the header, greeting, search, chip row, recap and group header take about 70% of the height above the dock, leaving **one visible note** (`ux/c21.png`). Collapse the greeting and recap on small heights, or let them scroll away.
- **Card and sheet separation.** Card versus page is **1.09:1** in light (`#FFFFFF` on `#F5F6F6`) and **1.12:1** in dark (`#1E1E1E` on `#131312`), with no border. The dark sheet versus the dimmed page is 1.16:1. `05-design.md` itself calls a 1.20:1 hairline inadequate. Add a 1 px `outlineVariant` border or raise the fill step.
- **Accent discipline.** The spec reserves the accent for "Nex is doing something". The shipped UI uses it for Ask, "Add caption", "See what Nex made of this", Summarize and the Save search link. Keep the accent for state and use neutral text buttons for the rest.
- **Detail actions.** The spec says the actions are pinned, not hidden in an overflow. v1.30.0 moved Pin, Remind and Delete into More actions (`ux/24_more_actions_s.png`). Either update the spec or promote Pin and Remind. Also hide actions that can't apply (Copy on voice, "Show in full" on media).
- **Timeline cards** no longer show the relative time or tags the spec requires (removed in v1.30.0). Update `05-design.md` or restore a quiet metadata line.
- **The search box can be hidden** (Home layout) even though the spec fixes its position. Pull-down still works, but discoverability drops.
- **Large text (2.0×)** reflows without clipping, but icons don't scale, and the 48 dp search pill gets tight (`ux/c20.png`). Consider scaling icons modestly, or giving the pill a minimum height based on the text scaler.
- **Desktop (Windows).** There's no minimum window size (`windows/runner` doesn't handle `WM_GETMINMAXINFO`), no right-click menu, and no keyboard path for the swipe-only Delete and Add Tag — only Ctrl+N and Ctrl+F exist. There's also almost no hover styling (one `MouseRegion` in the code base).
- **Photo edits** save full-resolution PNGs. Consider JPEG or WebP for storage and backup size (see the earlier audit).

---

## 4. Unverified risks

- **Onboarding** and the true empty-timeline state (needs a fresh install).
- **Windows runtime:** not built on this host (missing ATL and Android/VS components). §3 is from code only.
- **TalkBack reading order:** inferred from the accessibility tree, not tested with TalkBack running.
- **Liquid Glass legibility** over saturated or photo backgrounds was only checked over the plain background.
- **High-contrast mode:** the opaque fallback the spec promises was not exercised.
- **Persian multiline selection-handle bug** (open in HANDOFF): not retested.

---

## 5. What works well

- Reduced motion is honoured across animated widgets (`disableAnimationsOf` in the banner, receipt, edge glow, border beam, recorder).
- The voice recorder matches the spec: Stop is the largest control.
- The search "no matches" state shows the closest match instead of an empty box.
- Group delete confirms. Link validation is inline and clear. The Recurring empty state is helpful.
- The full-screen photo viewer handles double-tap zoom well.
- RTL mirroring of text, sheets and the capture row is largely correct. At 2× font scale, layouts reflow without clipping.
- Assistant write actions are gated by confirmation cards.

---

## 6. Changes made during the audit (all restored)

- Font scale 2.0 → 1.0.
- `wm size`/`wm density` override → reset.
- Airplane mode on → off.
- `show_ime_with_hard_keyboard` 0 → 1 → 0.
- App language Persian → System.
- Liquid Glass on → off.
- Keep-awake process stopped.

Left behind: one text note "UX audit capture test". A voice note was also saved during the session — I started the recording, but someone else ended it. The Dark theme and the granted mic permission were changed by the other emulator user, and I left them as they were.
