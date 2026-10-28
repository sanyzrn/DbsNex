# Nex on the desktop (2.3.6 →)

Nex builds for Windows (ADR-024) but has never been designed for a wide
window: it is the phone app in a bigger frame. This is what a review at
1440 × 900 found, what the desktop should look like, and the phases that get
there. It is written for `apps/client`; the website and the phone are not
touched by any of it.

## What the review found

Screens were rendered from the real widgets at 1440 × 900, light and dark,
English and Persian (the same way the store screenshots are made).

1. **One column in a sea of space.** The timeline is a 760 px column; the
   rest of the window is empty. Everything else is *not* capped at all:
   Settings, Library, Tools, Recurring and Tags run edge to edge, so a row is
   1400 px of text with a chevron at the far end, and the Cycle ring is a
   metre across.
2. **Phone chrome on a desktop.** A floating capsule dock with five icons
   sits in the middle of the window, the home header is a phone header (logo,
   greeting, a layout button), pages slide in from the side, and a note or a
   settings sheet rises from the bottom as a 640 px panel in the middle of
   nowhere. There is no sidebar, no hover, no right-click, no keyboard
   navigation beyond Ctrl+N and Ctrl+F.
3. **Too big, too busy.** The type scale and the 48 px touch targets are made
   for a thumb: body 14–16, titles 18–22, rows 56 px, cards 96 px. On a mouse
   everything is a size too large, and screens that stack many cards (Tools,
   Library, Settings, Appearance) read as noisy because every card has its
   own fill, border, icon tile and chevron.
4. **No density.** Nothing reads the window: there is one text scale, one
   card height, one spacing set. Content never reflows into columns.
5. **What is already good.** The data layer, search, the AI panel, the
   modules and the dialogs are platform-neutral and need no change; the
   theme (colour, type, motion, RTL) is solid; `NexSpacing`, `NexRadius`,
   `nexShowSheet` and `NexPageRoute` are single doors, so most desktop
   behaviour can be added in a handful of places instead of in 200 screens.

## The look

The reference is a calm notes app: a narrow left rail with small caps
section labels and counts, a quiet search field across the top with a
grid/list switch, and a grid of cards that are mostly white space — a title,
three lines of text, a tag and a time, a one-pixel border, a hairline above
the footer.

- **Small.** Body 13, secondary 12, section labels 11 in capitals with
  letter-spacing, titles 14 semi-bold. Rows 36 px, icons 18 px. The desktop
  text scale is 0.9 of the phone's (and the person's own size choice still
  applies on top of it).
- **Quiet.** One surface colour, one hairline. No card inside a card, no
  tinted tile behind every icon, no chevron on a row that is obviously
  tappable. Colour is for meaning: a tag's dot, a card's tint, the accent.
- **Wide, then wider.** A rail of 232 px; content that reads (settings,
  lists, a note) stops at 760–880 px and centres; content that browses
  (notes) fills the window in columns of 260–320 px.
- **Mouse and keyboard first.** Hover states, right-click menus, arrow keys
  in the grid, Enter to open, Esc to close, Ctrl+N / Ctrl+F / Ctrl+, and a
  visible shortcut on the controls that have one.
- **Same app.** Persian and English, light and dark, right-to-left and
  left-to-right all keep working; the rail moves to the right in Persian.

## Rules for the work

- Desktop layout is chosen by **window width ≥ 1000 dp** (a phone, a
  tablet in portrait and every existing test at 800 × 600 stay as they
  are). It is decided once, in the shell, and read through `nexIsDesktop`.
- New desktop code lives in `lib/desktop/`; the phone files only gain a
  condition at a door. No file grows past the 800-line limit.
- Everything follows `docs/16-design-language.md` and the consistency
  register; a desktop component that would be a second way of doing
  something replaces the first.
- Every phase ends with screenshots at 1440 × 900 (and 1000 × 700) in all
  four combinations, the phone screenshots unchanged, `flutter analyze`
  clean and the tests that cover what moved.

## Phases

### Phase 1 — The frame (2.3.6)
The pieces every screen needs, so that nothing is stretched or oversized any
more even before a single screen is redesigned.
- `lib/desktop/`: the breakpoint, `NexDesktopScope`, `nexIsDesktop`.
- The shell: a left rail (right in Persian) with the wordmark, **New note**,
  Notes, Recurring, Library, Tools, Settings, and the tags with their
  colours and counts; it replaces the floating dock; the content area is
  what the pages see as their window.
- Desktop type scale and compact density.
- Pages: a content width of 880 centred, a fade instead of the phone slide,
  no swipe-back; the back arrow stays.
- Sheets: `nexShowSheet` opens a centred dialog (width 560, up to 85 % of
  the height, rounded on all corners) instead of a bottom sheet.
- Done when: every screen in the review set renders without a stretched row
  and the home screen has no dock.

### Phase 2 — Home (2.3.6)
- Top bar: search field (Ctrl+F) with the grid/list switch and the layout
  menu; **New note** lives in the rail and in Ctrl+N.
- A new desktop note card (title, preview by type, tag chip, time, a pin and
  a ⋯ menu on hover) in a grid of 260–320 px columns with section labels
  (Pinned, then each day) instead of the phone's rows; tinted by the first
  tag's colour; list mode keeps one column of compact rows.
- The sponsor card, the recap and the empty states fit the grid.
- Selection: Ctrl/Shift+click and the bar across the top of the grid.
- Done when: the home screenshot sits next to the reference without
  embarrassment.

### Phase 3 — A note, and the keyboard
- The open note as a centred dialog or a right-hand panel (decide with the
  Phase 2 screenshots), with the AI panel as a second column when wide.
- Right-click menus on cards and on text, hover actions, drag-and-drop of
  files onto the window (capture), arrow-key navigation in the grid,
  Enter/Esc/Delete, Ctrl+, for settings, a shortcuts sheet (`?`).

### Phase 4 — The other pages
- **Settings**: two panes (groups on the left, the group on the right),
  rows of 40 px, no per-row fills.
- **Library, Tags, Threads, Archive, Trash**: one list style with a hairline
  between rows, counts at the end, hover.
- **Recurring**: list on the left, calendar on the right.
- **Tools / Vault**: a tidy grid of small tiles; vault lists as tables.
- **Profile, Cycle, Guide, Appearance, Intelligence, Backup**: widths,
  the Cycle ring capped at 360, the guide with its table of contents beside
  the text.

### Phase 5 — Windows itself
- Minimum window size (900 × 600), remembered size and position, the title
  bar and icon, taskbar badge for due reminders, optional tray and global
  quick-capture hotkey (the specification already lists both as future).
- The installer and the update path, tested on a real Windows machine (none
  of this can be verified from CI alone), the release workflow's Windows job
  switched on, and a Windows download on the website.

## Out of scope
macOS and Linux builds, sync, and anything that changes the data.
