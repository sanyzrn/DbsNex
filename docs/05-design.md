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

## Typography

A single, highly legible sans-serif family is used throughout (a system-native font such as Inter, SF Pro, or Segoe UI, depending on platform) to keep footprint low and rendering native-feeling. Monospace is used sparingly, only for technical/data contexts (timestamps, counts, debug info), never for body content.

| Role | Example Use | Weight |
|---|---|---|
| Display | Onboarding/empty states only | Semibold |
| Title | Note detail heading, section headers | Semibold |
| Body | Note content, capture input | Regular |
| Caption | Timestamps, tag chips, metadata | Regular / Medium |

- Line height is generous (1.4–1.6×) to preserve the "light" feeling and support long-form text readability.
- No more than two font weights are used on a single screen at once.

---

## Color Philosophy

Nex is deliberately black-and-white first. The surface — backgrounds, cards, chips, borders, icons — carries no decorative color anywhere. The one exception is a **tag accent dot**, and it exists to carry the user's own meaning, not the product's: see [Tag Accent Color](#tag-accent-color) below. This supersedes the original blanket "no color-coding" rule — see [ADR-021](./10-decisions.md#adr-021--optional-user-chosen-tag-accent-color).

| Token | Light Mode | Dark Mode | Usage |
|---|---|---|---|
| `bg-primary` | `#FFFFFF` | `#0A0A0A` | App background |
| `bg-elevated` | `#F5F4F2` | `#171717` | Cards, sheets |
| `text-primary` | `#111113` | `#FAFAFA` | Primary text/content (mockup `--text`) |
| `text-secondary` | `#8B8B90` | `#A3A3A3` | Timestamps, metadata, captions (mockup `--text-soft`) |
| `border` | `#EBEAE8` | `#262626` | Dividers, card outlines (mockup `--border`) |
| `accent` | `#111113` (inverted per mode) | `#FAFAFA` | The `+` action, active states — never a "brand color," always the inverse of the background |

- **Dark mode is a first-class, symmetric palette**, not an inverted afterthought — capture often happens in low light, at night, or first thing in the morning.
- Aside from the tag accent dot, the **only** deliberate use of stronger visual weight is the `+` capture action and active/recording states (e.g., a pulsing indicator during voice capture).

### Tag Accent Color

A tag may optionally carry a single small accent color, shown only as a small dot (6–8px) next to the tag's label — never as a filled chip, a colored card border, or a colored background. Everything else about the tag (the chip shape, the text, the card it's attached to) stays neutral.

- **User-chosen, not system-assigned.** The color is not derived automatically from the tag's name or category. The user picks it — or doesn't — when creating or editing a tag, from a small, restrained, low-saturation palette (5–6 options, no free color picker). This is deliberate: it lets a person encode *their own* meaning — e.g., using red for "urgent/important" regardless of which tag it's attached to, and a neutral gray dot (or no dot at all) for everything low-priority — rather than the product imposing a fixed category-to-color mapping the user has no say in.
- **Optional, with a neutral default.** An unset tag renders with no dot, or a neutral gray dot. Nothing about search, filtering, or capture requires a color to be set.
- **Never at capture time.** Color, like the tag itself, is only ever assigned when organizing — after a note is already safely captured. This keeps the rule from [ADR-001](./10-decisions.md#adr-001--capture-has-zero-mandatory-fields) intact: capture still has zero decisions.
- **Small enough to stay quiet.** The dot is a recognition aid, not a design statement — it should be visible at a glance without turning the Timeline into a colorful list.

### Comfort Mode

Dark theme alone does not solve late-night eye strain, and can make it worse. In a genuinely dark room, a very high-contrast pairing — pure white text on pure black — causes a real, well-documented perceptual effect (halation/glare): the eye perceives a glow around high-contrast edges, which is often *more* fatiguing than a well-lit screen in a well-lit room, not less. Separately, blue-heavy light in the evening suppresses melatonin production regardless of overall brightness. Neither problem is fixed by "make it dark" on its own.

**Comfort Mode** is therefore an independent toggle, orthogonal to the Light/Dark theme choice — not a third theme. It can be switched on or off within either theme, in Settings, and does two things at once:

1. **Lowers contrast**, moving both ends of the palette inward: background lightens toward warm off-black in Dark, or softens toward warm off-white in Light; text moves away from pure `#FFFFFF`/`#000000` toward a warm off-white or warm charcoal.
2. **Shifts color temperature warmer** (reduces the blue channel across backgrounds and text), the same principle behind Night Shift / f.lux, to reduce blue-light exposure during evening and night capture.

| Token | Light, Comfort off | Light, Comfort on | Dark, Comfort off | Dark, Comfort on |
|---|---|---|---|---|
| `bg-primary` | `#FFFFFF` | `#F7F1E6` | `#0A0A0A` | `#17130F` |
| `text-primary` | `#111113` | `#2E2A22` | `#FAFAFA` | `#D9CFC0` |

Both combinations retain WCAG 2.1 AA contrast for body text — Comfort Mode reduces *glare*, not *legibility*.

- **Default off**, in both themes; a person opts in once they notice the problem, consistent with Nex never making an aesthetic decision on the user's behalf without cause.
- **Manual toggle in v1.x.** Automatically scheduling it by time of day (sunset/sunrise, like Night Shift) is a reasonable future addition but adds scheduling and location complexity not justified for the initial release — see [ADR-023](./10-decisions.md#adr-023--comfort-mode-as-an-independent-axis-from-lightdark-theme).
- **Applies everywhere**, not just the Timeline — Capture Sheet, Search, and Settings all inherit the same tokens, since the moment this exists to protect (a 2 AM capture) touches the capture flow first.

---

## Components

| Component | Purpose | Design Notes |
|---|---|---|
| **Capture Button (`+`)** | Universal entry point to text/voice/photo capture | Always visible on the Timeline, fixed position, largest single interactive element on screen |
| **Capture Sheet** | Presents the three capture types | Appears instantly (no loading state), dismissible by outside tap |
| **Timeline Card** | Represents one note in the stream | Adapts preview to content type (text snippet / waveform + duration / photo thumbnail); shows relative timestamp and tag chips if present |
| **Tag Chip** | Represents a single tag | Neutral chip shape and text; an optional small accent dot (user-chosen, see [Tag Accent Color](#tag-accent-color)) may render beside the label. Rounded, removable via inline "×" in edit contexts |
| **Search Bar** | Entry point + live query field | Paired with filter affordances (tag / date / type) that expand without navigating away |
| **Filter Control** | Tag / date / content-type filters | Simple toggles/pills, combinable, always reversible with a single "clear" action |
| **Note Detail Sheet** | Expanded view of a single note, tag editing | Lightweight overlay, not a full context switch |
| **Voice Recorder Bar** | Active recording state | Live waveform and elapsed time; the stop action is the single largest control on screen |
| **Empty State** | Shown only when the Timeline has zero notes | A single, quiet prompt pointing at the `+` button — never a tutorial carousel |
| **Swipe Action Reveal** | Quick Delete / Add Tag from the Timeline | See [Swipe Actions](#swipe-actions) below |
| **Settings Sheet** | Holds the small set of v1 preferences (swipe mapping, theme) | Reached by tapping the avatar; a single sheet, not a nested settings app |

---

## Swipe Actions

Each Timeline card supports a horizontal swipe to reveal one quick action per edge, per [FR-2.6–2.8](./02-product-specification.md#fr-2--timeline).

- **Reveal, don't confirm.** Dragging a card exposes a colored panel behind it in real time, tracking the finger 1:1; there is no modal or confirmation step for either action.
- **Delete is destructive-looking, but never actually destructive.** Its reveal panel uses the only saturated warning-style color in the entire system (a muted red), paired with a trash icon and the word "Delete" — because this is the one place in Nex where a stronger visual warning is earned. The note is soft-deleted (per [`02-product-specification.md`](./02-product-specification.md#data-model)) and a brief "Note deleted · Undo" toast follows, so the action is always reversible for a short window.
- **Add Tag stays neutral.** Its reveal panel uses a plain surface tone, not a color, since it isn't destructive and doesn't need to compete visually with Delete.
- **Threshold, not a hair-trigger.** A short drag re-settles the card closed; only a deliberate drag past a clear threshold snaps the action panel fully open. This keeps ordinary vertical scrolling from ever misfiring a swipe.
- **One open card at a time.** Starting a swipe on any card closes whichever other card was previously revealed.
- **The mapping is configurable, the action set is not.** Which edge triggers Delete vs. Add Tag is a Settings preference (so the gesture can match a person's left- or right-hand swiping habit); which two actions exist is fixed, deliberately, per [ADR-022](./10-decisions.md#adr-022--configurable-swipe-actions-limited-to-a-fixed-two-action-set).

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
