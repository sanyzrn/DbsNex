# Nex — Design System

> Companion to [`01-product-vision.md`](./01-product-vision.md#ux-philosophy). Minimal. Black and white. Fast. Light. Calm.

**Status:** Authoritative · **Owner:** Design · **Last updated:** 2026

Nex's interface must feel **weightless** — like a fast capture surface, never like project-management software. Every visual decision reinforces a single feeling: *this is the fastest place to drop a thought.*

Guiding statement: *if a design element doesn't help the user capture or find something faster, remove it.*

---

## Design Language

- Black and white as the primary palette in both light and dark themes; no decorative color. Any accent is reserved for state (e.g., an active capture or confirmation), never for brand or decoration.
- Generous white space; content is never cramped against edges or against other content.
- Highly legible typography at every size.
- Short, purposeful motion — never decorative, never delayed.
- No skeuomorphism, no gradients-as-decoration, no illustrations that don't carry information.

---

## UI Principles

1. **One primary action per screen.** The Timeline's primary action is `+`. The Capture screen's primary action is "provide content." Nothing competes with it visually.
2. **No modal interrogations.** Dialogs that ask the user to decide something before proceeding (name it, file it, choose a type beyond the initial three) are disallowed by design policy.
3. **Progressive disclosure.** Tags, timestamps, and metadata are visible but never demand interaction — available when wanted, invisible when not.
4. **Consistent, predictable placement.** The `+` action and Search entry point occupy fixed, muscle-memory positions across the Timeline at all times.
5. **Content is the interface.** Cards show the user's own words, recordings, and photos — not decorative chrome.
6. **Honest affordances.** If something has a limitation (e.g., audio is tag/date-only searchable in v1), show it plainly rather than hiding it.
7. **Every screen is understood in under 30 seconds**, with zero onboarding, consistent with the [non-negotiable principles](./01-product-vision.md#non-negotiable-principles).

---

## Typography and Colour

> The tokens themselves live in `packages/ui/lib/tokens/nex_tokens.dart`, and that
> file is the source of truth. This section records the reasoning; the values are
> not repeated here, because a table of hex codes in a document is a copy that
> drifts — as this one did, describing a white page and a monochrome accent long
> after the app shipped an off-white page and an ink-blue one.

### Tag Accent Color

A tag may optionally carry a single small accent color, shown only as a small dot (6–8px) next to the tag's label — never as a filled chip, a colored card border, or a colored background. Everything else about the tag (the chip shape, the text, the card it's attached to) stays neutral.

- **User-chosen, not system-assigned.** The color is not derived automatically from the tag's name or category. The user picks it — or doesn't — when creating or editing a tag, from a full colour picker ([ADR-021](./10-decisions.md#adr-021--optional-user-chosen-tag-accent-color) originally proposed a fixed 5–6 swatch palette; it shipped free-form). This is deliberate: it lets a person encode *their own* meaning — e.g., using red for "urgent/important" regardless of which tag it's attached to, and a neutral gray dot (or no dot at all) for everything low-priority — rather than the product imposing a fixed category-to-color mapping the user has no say in.
- **Optional, with a neutral default.** An unset tag renders with no dot, or a neutral gray dot. Nothing about search, filtering, or capture requires a color to be set.
- **Never at capture time.** Color, like the tag itself, is only ever assigned when organizing — after a note is already safely captured. This keeps the rule from [ADR-001](./10-decisions.md#adr-001--capture-has-zero-mandatory-fields) intact: capture still has zero decisions.
- **Small enough to stay quiet.** The dot is a recognition aid, not a design statement — it should be visible at a glance without turning the Timeline into a colorful list.

### Comfort Mode

Dark theme alone does not solve late-night eye strain, and can make it worse. In a genuinely dark room, a very high-contrast pairing — pure white text on pure black — causes a real, well-documented perceptual effect (halation/glare): the eye perceives a glow around high-contrast edges, which is often *more* fatiguing than a well-lit screen in a well-lit room, not less. Separately, blue-heavy light in the evening suppresses melatonin production regardless of overall brightness. Neither problem is fixed by "make it dark" on its own.

**Comfort Mode** is therefore an independent toggle, orthogonal to the Light/Dark theme choice — not a third theme. It can be switched on or off within either theme, in Settings, and does two things at once:

1. **Lowers contrast**, moving both ends of the palette inward: background lightens toward warm off-black in Dark, or softens toward warm off-white in Light; text moves away from pure `#FFFFFF`/`#000000` toward a warm off-white or warm charcoal.
2. **Shifts color temperature warmer** (reduces the blue channel across backgrounds and text), the same principle behind Night Shift / f.lux, to reduce blue-light exposure during evening and night capture.

Comfort has its own full ramp rather than a tint over the default one — its
borders are drawn from the warm ramp too, because reusing the cool grey left a
visibly off-hue edge on a cream ground. See the `*Comfort` tokens in
`nex_tokens.dart`.

All four combinations retain WCAG 2.1 AA contrast for body text — Comfort Mode reduces *glare*, not *legibility*.

- **Default off**, in both themes; a person opts in once they notice the problem, consistent with Nex never making an aesthetic decision on the user's behalf without cause.
- **Manual toggle in v1.x.** Automatically scheduling it by time of day (sunset/sunrise, like Night Shift) is a reasonable future addition but adds scheduling and location complexity not justified for the initial release — see [ADR-023](./10-decisions.md#adr-023--comfort-mode-as-an-independent-axis-from-lightdark-theme).
- **Applies everywhere**, not just the Timeline — Capture Sheet, Search, and Settings all inherit the same tokens, since the moment this exists to protect (a 2 AM capture) touches the capture flow first.

### Home-screen widgets

The Android home screen is the one surface outside the app that can shorten the
capture path, so Nex ships four widgets there — see
[ADR-029](./10-decisions.md#adr-029--the-home-screen-widget-grows-from-one-dead-button-into-four-real-widgets):

- **Quick capture** — opens straight into the capture sheet.
- **Voice memo** — one tap starts recording.
- **Photo** — one tap opens the camera capture flow.
- **Recent notes** — the newest notes, scrollable, each opening its note.

They are tone-matched to the app's own tokens rather than to the launcher: the same
rounded card, the ink-blue accent on one-tap actions, a neutral disc for content
rows, secondary text for metadata, and light/dark variants resolved from the
device's night mode. RTL layouts follow the locale. A widget is decoration-plus-one-
tap, never a dashboard: the only interactive content is the notes list, and even
that leads back into the app for anything beyond a glance.

---

## Components

| Component | Purpose | Design Notes |
|---|---|---|
| **Capture Button (`+`)** | Universal entry point to text/voice/photo capture | Always visible on the Timeline, fixed position, largest single interactive element on screen |
| **Capture Sheet** | Presents the three capture types | Appears instantly (no loading state), dismissible by outside tap |
| **Timeline Card** | Represents one note in the stream | Adapts preview to content type (text snippet / waveform + duration / photo thumbnail); shows relative timestamp and tag chips if present. **Every card is the same height** — two lines of preview and one line of metadata, filled or not. A card's height carried no meaning, so letting it vary only made the list ragged; a tag that does not fit the one line runs off the edge rather than wrapping onto a second |
| **Tag Chip** | Represents a single tag | Neutral chip shape and text; an optional small accent dot (user-chosen, see [Tag Accent Color](#tag-accent-color)) may render beside the label. Rounded, removable via inline "×" in edit contexts |
| **Search Bar** | Entry point + live query field | Paired with filter affordances (tag / date / type) that expand without navigating away |
| **Filter Control** | Tag / date / content-type filters | Simple toggles/pills, combinable, always reversible with a single "clear" action |
| **Note Detail Sheet** | Expanded view of a single note, tag editing, and the secondary actions of FR-2.9 | Sized to the note: a long one opens at reading height and scrolls, a short one stays short. The actions are labelled icons pinned under the body, not hidden in an overflow menu in the corner — the hardest place on a phone to reach, and one that said nothing about what was inside it |
| **Voice Recorder Bar** | Active recording state | Live waveform and elapsed time; the stop action is the single largest control on screen |
| **Empty State** | Shown only when the Timeline has zero notes | A single, quiet prompt pointing at the `+` button — never a tutorial carousel |
| **Swipe Action Reveal** | Quick Delete / Add Tag from the Timeline | See [Swipe Actions](#swipe-actions) below |
| **Settings Sheet** | Holds every v1 preference, grouped — see [Settings](./02-product-specification.md#navigation) | Reached in one tap from the Timeline; a single scrolling sheet, not a nested settings app. Preferences are grouped into labelled cards (`bg-elevated`, `card-radius`, 1px `border`) with a header row per group, because a flat run of twenty-odd tiles is not scannable. Opens with a drag handle and clear of the status bar |

---

## Typography and Colour

The interface is set in **one typeface on every platform** — Inter, with Vazirmatn for
Persian, both shipped as assets. Leaving it to the OS meant Roboto on Android, Segoe UI
Variable on Windows and SF Pro on iOS: three faces with three x-heights and three sets of
line-break points, so the same screen had a different density depending on where it was
opened.

All fifteen Material text slots are defined. Six were, which left every button, chip and
list-tile label typeset by Material's defaults — a face and a letter-spacing chosen for
Roboto, applied to whatever the platform happened to load.

Colour is **declared, not seeded**. Every surface is drawn from one warm neutral ramp, and
three rules hold:

- A card's fill is not the page's fill. They were both `#FFFFFF`, which left a 1px hairline at
  1.20:1 as the only thing separating the app's primary tap target from the page behind it.
- A boundary and a divider are different tokens. `outline` marks something you can act on and
  clears 3:1; `outlineVariant` separates rows and is deliberately quiet.
- **One accent, and it means "Nex is doing something"** — the caret, recording, focus rings,
  the active filter, the commit receipt. Rationing it is what makes it information rather than
  decoration. It is an ink blue rather than a warm one because the destructive red and the
  amber in the tag palette already sit in that part of the wheel, and "delete" and "recording"
  are the two moments that must never be confusable.

Contrast is asserted in tests rather than stated here, so a value that misses its floor fails
the build instead of aging quietly in a table.

---

## Search

Search is not a place you go. The query field is part of the Timeline's own list, above the
first card, with the list resting scrolled just past it — so **pulling down brings it in**, and
because that is ordinary scrolling rather than an overscroll effect it behaves the same under
Android's clamping physics and iOS's bouncing ones. The header icon and the desktop shortcut
perform the same reveal; a gesture is a shortcut, never the only door.

Results replace the cards in place. "Find in seconds" cannot be true if finding starts with a
route push and a transition.

---

## Swipe Actions

Each Timeline card supports a horizontal swipe to reveal one quick action per edge, per [FR-2.6–2.8](./02-product-specification.md#fr-2--timeline).

- **Reveal, don't confirm.** Dragging a card exposes a colored panel behind it in real time, tracking the finger 1:1; there is no modal or confirmation step for either action.
- **Delete is destructive-looking, but never actually destructive.** Its reveal panel uses the only saturated warning-style color in the entire system (a muted red), paired with a trash icon and the word "Delete" — because this is the one place in Nex where a stronger visual warning is earned. The note is soft-deleted (per [`02-product-specification.md`](./02-product-specification.md#data-model)) and a brief "Note deleted · Undo" toast follows, so the action is always reversible for a short window.
- **Add Tag stays neutral.** Its reveal panel uses a plain surface tone, not a color, since it isn't destructive and doesn't need to compete visually with Delete.
- **Threshold, not a hair-trigger.** A short drag re-settles the card closed; only a deliberate drag past a clear threshold snaps the action panel fully open. This keeps ordinary vertical scrolling from ever misfiring a swipe.
- **One open card at a time.** Starting a swipe on any card closes whichever other card was previously revealed.
- **The panel is a capsule, and it belongs to the card.** It is laid out inside the same gutter the card keeps, so it starts where the card starts instead of running to the physical screen edge past it, and it is fully rounded at every width — a narrow vertical pill at the beginning of a swipe, widening into a lozenge. One shape throughout, never a rectangle bleeding off the side.
- **The glyph waits for room.** Below roughly 54px of travel the panel is a bare capsule; past that the icon and its label fade in together, centred in the panel rather than in the space the swipe opened.
- **The icon reacts at the commit point.** Crossing the point where letting go performs the action is the one moment in the gesture with a consequence, and it now gets a beat of motion — the glyph swells, tips and springs back. A static scale step is a state change the eye has to notice; motion is one the hand feels it caused.
- **Each edge is configured on its own.** Settings binds the leading and the trailing edge independently, from the actions that exist — Delete, Add Tag, or None — so the gesture can match a person's swiping habit, and someone who wants only one swipe can have only one. An edge set to None does not move at all. See [ADR-022](./10-decisions.md#adr-022--swipe-actions-are-configurable-per-edge-from-an-open-set).

---

## Icons

A single, consistent icon set (line-style, uniform stroke width) is used throughout — no mixing of filled and outlined families. Icons are used only where they communicate faster than text (capture types, play/stop, search, filters) — never as decoration. Every icon-only control has an accessible label.

---

## Animations

Animation exists only to **confirm**, never to **delight for its own sake**.

- **Duration:** 120–200 ms for micro-interactions (button press, chip add/remove); 200–300 ms for sheet transitions.
- **Easing:** standard ease-out for entrances, ease-in for exits.
- **Purposeful motion only:** the Capture Sheet slides/fades in to confirm readiness; a saved note animates briefly into position at the top of the Timeline to confirm "it's there"; voice recording uses a live waveform as continuous, functional motion.
- **No motion that delays interaction.** Nothing animates *before* becoming interactive.
- **Respects reduced-motion settings** at the OS level — non-essential transitions become instant state changes.

---

## Accessibility

Accessibility is core functionality, not a compliance checkbox — a slow or confusing experience for any user contradicts Nex's core promise.

- **Contrast:** WCAG 2.1 AA (4.5:1 body text, 3:1 large text) in both palettes.
- **Tap targets:** Minimum 44×44pt, most critically the `+` action and the voice stop control.
- **Screen reader support:** Every icon-only control has a descriptive accessible label; Timeline cards announce content type, preview/transcription placeholder, timestamp, and tags in one coherent read-out.
- **Dynamic type:** UI text scales with system font-size settings without breaking layout or truncating input.
- **Voice capture alternative:** Text and photo capture remain full alternatives for users who cannot or prefer not to use audio input.
- **Motion sensitivity:** All animation respects OS-level "reduce motion."
- **Color independence:** No information is conveyed by color alone, by construction of the monochrome palette.
