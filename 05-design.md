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

Nex is deliberately black-and-white first. Color is a signal of meaning, never of style — using color to encode categories, priorities, or tags would subtly reintroduce organizational decision-making at the point of interaction.

| Token | Light Mode | Dark Mode | Usage |
|---|---|---|---|
| `bg-primary` | `#FFFFFF` | `#0A0A0A` | App background |
| `bg-elevated` | `#F5F5F5` | `#171717` | Cards, sheets |
| `text-primary` | `#0A0A0A` | `#FAFAFA` | Primary text/content |
| `text-secondary` | `#6B6B6B` | `#A3A3A3` | Timestamps, metadata, captions |
| `border` | `#E5E5E5` | `#262626` | Dividers, card outlines |
| `accent` | `#0A0A0A` (inverted per mode) | `#FAFAFA` | The `+` action, active states — never a "brand color," always the inverse of the background |

- **Tags are visually neutral** — simple bordered chips in `text-secondary`/`border` tones, never color-coded, so tag color never becomes an implicit categorization system users must maintain.
- **Dark mode is a first-class, symmetric palette**, not an inverted afterthought — capture often happens in low light, at night, or first thing in the morning.
- The **only** deliberate use of stronger visual weight is the `+` capture action and active/recording states (e.g., a pulsing indicator during voice capture).

---

## Components

| Component | Purpose | Design Notes |
|---|---|---|
| **Capture Button (`+`)** | Universal entry point to text/voice/photo capture | Always visible on the Timeline, fixed position, largest single interactive element on screen |
| **Capture Sheet** | Presents the three capture types | Appears instantly (no loading state), dismissible by outside tap |
| **Timeline Card** | Represents one note in the stream | Adapts preview to content type (text snippet / waveform + duration / photo thumbnail); shows relative timestamp and tag chips if present |
| **Tag Chip** | Represents a single tag | Neutral color, rounded, removable via inline "×" in edit contexts |
| **Search Bar** | Entry point + live query field | Paired with filter affordances (tag / date / type) that expand without navigating away |
| **Filter Control** | Tag / date / content-type filters | Simple toggles/pills, combinable, always reversible with a single "clear" action |
| **Note Detail Sheet** | Expanded view of a single note, tag editing | Lightweight overlay, not a full context switch |
| **Voice Recorder Bar** | Active recording state | Live waveform and elapsed time; the stop action is the single largest control on screen |
| **Empty State** | Shown only when the Timeline has zero notes | A single, quiet prompt pointing at the `+` button — never a tutorial carousel |

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
