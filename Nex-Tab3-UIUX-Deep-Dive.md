# Nex — Tab 3: Visual & UI/UX Deep-Dive

> **Based on code inspection — not direct visual observation**
>
> No screenshots or running build were available, so nothing here comes from looking at the app. Everything is read from the committed Flutter source: the token file packages/ui/lib/tokens/nex_tokens.dart, the three shared widgets in packages/ui/lib/widgets/, and the seven screens plus five widgets under apps/client/lib/. Hex values, sizes, paddings, radii and widget structure are quoted directly and marked CONFIRMED. Anything about how it feels, renders on a specific device, or behaves at runtime is marked INFERRED or ASSUMPTION and flagged inline.

**Confirmed data points:** 31 · **Inferred:** 7

**Source files inspected:**
- `packages/ui/lib/tokens/nex_tokens.dart`
- `packages/ui/lib/widgets/note_card.dart`
- `packages/ui/lib/widgets/tag_filter_row.dart`
- `packages/ui/lib/widgets/swipeable_note_card.dart`
- `apps/client/lib/screens/timeline_screen.dart`
- `apps/client/lib/screens/search_screen.dart`
- `apps/client/lib/screens/settings_sheet.dart`
- `apps/client/lib/screens/note_detail_sheet.dart`
- `apps/client/lib/screens/update_sheet.dart`
- `apps/client/lib/widgets/capture_sheet.dart`
- `apps/client/lib/widgets/empty_timeline.dart`

---

## Table of Contents

- [1. Current State Analysis](#1-current-state-analysis)
  - [1.1 Findings](#11-findings)
  - [1.2 Current Colour Palettes](#12-current-colour-palettes)
  - [1.3 Current Typography](#13-current-typography)
- [2. Redesign Proposal](#2-redesign-proposal)
  - [2.1 Brand Thesis](#21-brand-thesis)
  - [2.2 New Colour System](#22-new-colour-system)
  - [2.3 New Typography System](#23-new-typography-system)
  - [2.4 Spacing, Radius, Elevation & Motion](#24-spacing-radius-elevation--motion)
  - [2.5 Component Specs](#25-component-specs)
  - [2.6 Information Architecture](#26-information-architecture)
  - [2.7 Signature Ideas](#27-signature-ideas)
  - [2.8 Before / After Summary](#28-before--after-summary)
  - [2.9 Rollout Plan](#29-rollout-plan)

---

## 1. Current State Analysis

### 1.1 Findings

**Total findings:** 32 — critical: 6, major: 14, minor: 12

#### UI-01 — Every card boundary fails WCAG non-text contrast — cards are effectively invisible
- **Area:** Colour
- **Severity:** critical
- **Confidence:** confirmed

**Evidence**  
NoteCard draws `Material(color: colorScheme.surface)` with `side: BorderSide(color: colorScheme.outline)`. surface = #FFFFFF and outline = #EBEAE8, so a card sits on a white scaffold with a 1px hairline at 1.20:1. Dark mode is #262626 on #0A0A0A = 1.31:1. WCAG 2.1 SC 1.4.11 requires 3:1 for boundaries that convey information.

**Why it matters**  
The card is the only container in the timeline and it is the tap target for opening a note. With fill and page identical, the border alone carries the boundary — and at 1.2:1 that hairline is below the threshold at which many users can resolve it at all, especially on a glossy phone screen outdoors. The same 1px outline is reused for dividers and the empty-state ghost frames.

**Fix**  
Separate card fill from page fill (paper-on-desk), add a real elevation token, and raise the border to ≥3:1. Never let a single hairline be the only signal.

---

#### UI-07 — No typeface is specified on any platform except Windows
- **Area:** Type
- **Severity:** critical
- **Confidence:** confirmed

**Evidence**  
`fontFamily: !kIsWeb && Platform.isWindows ? 'Segoe UI Variable' : null`. There are no font assets in pubspec.yaml — the `flutter:` block declares only `uses-material-design: true`.

**Why it matters**  
Android renders Roboto, iOS/macOS render SF Pro, Windows renders Segoe UI Variable. Three different typefaces with different x-heights, widths and optical sizes, so the same screen has three different densities and line-break points. For a product whose thesis is craft, the single most visible design decision has been delegated to the OS. It also means the Farsi locale falls back to whatever Arabic-script face each platform ships, with no metric relationship to the Latin face beside it.

**Fix**  
Ship a variable font as an asset and use it on every platform, with a matched Arabic-script companion for `fa`.

---

#### UI-13 — The primary filter controls are below every minimum tap-target guideline
- **Area:** Components
- **Severity:** critical
- **Confidence:** confirmed

**Evidence**  
`nexMinTapTarget = 44.0` is declared in the token file. `_TypeFilterButton` renders `EdgeInsets.symmetric(horizontal: 12, vertical: 8)` around a 16px icon = 32px tall. `_Pill` renders `symmetric(horizontal: 15, vertical: 8)` around 14px text ≈ 34px tall. `TagChip` on the note card passes `visualDensity: VisualDensity.compact`, which subtracts a further 8px from Material's already-32px chip.

**Why it matters**  
WCAG 2.5.8 asks for 24×24 minimum, Material for 48×48, Apple for 44×44, and the project's own token says 44. The entire tag filter row — the only way to filter the timeline — misses all three of the latter. These are horizontally scrolling targets, which is the hardest case for accurate acquisition.

**Fix**  
Enforce a 48dp minimum hit area on every interactive element, visually smaller if the design calls for it but padded out to 48.

---

#### UI-14 — No focus indicator exists — on a product that ships a first-class desktop target
- **Area:** Components
- **Severity:** critical
- **Confidence:** confirmed

**Evidence**  
The only focus affordance in the theme is `focusColor: primary.withValues(alpha: 0.16)`, a 16% fill tint. There is no FocusTheme, no outline, no `WidgetStateProperty` for focused borders, and no `FocusableActionDetector` in any custom widget. `_Pill`, `_TypeFilterButton` and `NoteCard` are all built on bare `InkWell`s.

**Why it matters**  
Windows is a shipped platform with a CI build job and an Inno Setup installer. A keyboard user tabbing through the timeline gets a 16% grey wash on a grey element — WCAG 2.4.7 Focus Visible fails, and practically the focus position is untrackable. The same applies to hardware-keyboard Android and to switch-access users.

**Fix**  
A 2px accent focus ring with a 2px offset on every interactive surface, defined once as a token.

---

#### UI-18 — Trash and Tag Manager are buried inside Settings
- **Area:** IA
- **Severity:** critical
- **Confidence:** confirmed

**Evidence**  
settings_sheet.dart imports and routes to `recently_deleted_screen.dart` and `tag_manager_screen.dart`. There is no other entry point to either.

**Why it matters**  
Recently Deleted is a *content location* — it holds the user's notes. Tag Manager is *content organisation*. Neither is a preference. A user hunting for a note they deleted by mistake has to reason their way to a gear icon, which is the least discoverable path in the app, and the swipe-to-delete gesture makes accidental deletion likely enough that recovery needs to be prominent.

**Fix**  
Promote both to a content-level surface reachable from the timeline, not from preferences.

---

#### UI-22 — The onboarding empty state flashes on every cold launch, even with thousands of notes
- **Area:** States
- **Severity:** critical
- **Confidence:** confirmed

**Evidence**  
`List<Note> notes = const [];` at field initialisation. `initState` fires `unawaited(_loadTimeline())`. `build` runs immediately and evaluates `notes.isEmpty && selectedTagId == null ? const EmptyTimeline() : ...`.

**Why it matters**  
The first frame after launch always satisfies that condition, so every user sees the full-screen 'Capture in seconds / there is no save button' onboarding screen before their timeline paints. For an existing user this is a jarring flash of marketing copy; for a slow cold start on a large library it may be visible for several hundred milliseconds. There is no loading state to distinguish 'empty' from 'not yet known'.

**Fix**  
Model the timeline as a tri-state (loading / empty / populated) and render a skeleton for the first.

---

#### UI-02 — The 56×56 icon box behind every note leading-icon is invisible in light mode
- **Area:** Colour
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
`_IconBox` fills with `surfaceContainerHighest` (= elevated, #F5F4F2) inside a card filled with surface (#FFFFFF). That is 1.10:1. In comfort light it is #F0E8DA on #F7F1E6 = 1.08:1.

**Why it matters**  
A deliberate, 56px-square design element renders as nothing but a floating glyph. The same box is the visual anchor of the empty state's three ghost rows, so the onboarding screen reads as three loose icons rather than three placeholder cards.

**Fix**  
Give the container a real tonal step (≥1.6:1 against the card) or drop the box and use a typed accent glyph instead.

---

#### UI-03 — `ColorScheme.fromSeed` is seeded from near-black, so every non-overridden role is undesigned grey
- **Area:** Colour
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
`ColorScheme.fromSeed(seedColor: primary)` where primary is #111113 (light) or #FAFAFA (dark). The `.copyWith` overrides only surface, onSurface, primary, onPrimary, secondary, outline, surfaceContainerHighest and error. Everything else — primaryContainer, secondaryContainer, tertiary, surfaceTint, inversePrimary, errorContainer, onSurfaceVariant, the surfaceContainer ramp — is generated from a seed with near-zero chroma.

**Why it matters**  
Material 3 derives a tonal palette from the seed's HCT hue and chroma. A #111113 seed has chroma ≈ 0, so every generated role is a flat grey with no designed relationship to anything. `inversePrimary` is used live as the Undo action colour in the delete SnackBar — a colour nobody chose. Any future Material component (Switch, Slider, Badge, DatePicker) will pull unstyled greys.

**Fix**  
Stop seeding. Declare the full ColorScheme explicitly from a token ramp so every role is intentional.

---

#### UI-04 — There is no accent colour anywhere in the product
- **Area:** Colour
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
The only non-greyscale values in the entire token file are swipeDelete #C0392B and swipeAddTag #4A5568. `primary` is the text colour. FilledButtons, the FAB, selected pills and focus tints all resolve to near-black on near-white.

**Why it matters**  
Minimalism is a legitimate stance, but with zero chroma nothing can signal *interactive* versus *static*, *live* versus *idle*, or *primary* versus *secondary* action without relying on size and position alone. The recording state, the focused input and the just-committed note — the three moments the product most needs to confirm — all have no colour channel available.

**Fix**  
Introduce exactly one rationed accent that means 'Nex is live', and spend it only on capture, focus, recording and active filter.

---

#### UI-08 — Only 6 of Material's 15 text styles are defined — including no `labelLarge`, which every button uses
- **Area:** Type
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
The TextTheme declares displaySmall, titleLarge, titleMedium, bodyLarge, bodyMedium, bodySmall. `labelLarge`, `labelMedium`, `labelSmall`, `titleSmall` and all five headline/display slots fall through to Material's built-in typography.

**Why it matters**  
Every button, chip and list-tile label in the app is typeset by Material's defaults rather than by the design system — 14px/w500 with Roboto's 0.1 letter-spacing baked in for a face that may not be Roboto. The nine undefined styles also carry Material's default colours rather than the `primary`/`secondary` the six defined styles set, so component text colour is resolved by a different mechanism than body text.

**Fix**  
Define the full scale explicitly. If a slot is unused, define it anyway so nothing falls through.

---

#### UI-09 — The scale is arbitrary and one size is sub-pixel
- **Area:** Type
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
30 → 22 → 17 → 16 → 14 → 12.5. The ratios are 1.36, 1.29, 1.06, 1.14, 1.12. `bodySmall` is 12.5 — a fractional size. `titleMedium` at 17 is an iOS convention dropped into a Material scale.

**Why it matters**  
titleMedium (17) and bodyLarge (16) are one point apart, so a heading and body text are near-indistinguishable except by weight — the hierarchy carries almost no size signal. 12.5px is below the 13px floor generally recommended for sustained secondary reading, and it is the style used for every date, every tag chip and every storage figure.

**Fix**  
Adopt a single modular ratio, round to even integers, and raise the caption floor to 13.

---

#### UI-11 — The spacing scale has two off-grid values and is bypassed everywhere anyway
- **Area:** Spacing
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
NexSpacing = 4, 8, 14, 16, 18, 24, 32. `contentGap: 14` and `cardInset: 18` are off any 4pt rhythm. Meanwhile the screens hardcode: `vertical: 5` (NoteCard outer padding), `spacing: 6, runSpacing: 5` (tag wrap), `horizontal: 15, vertical: 8` (filter pill), `horizontal: 20, vertical: 16` (anniversary row), `bottom: 118` (list padding), `fromLTRB(16, 0, 16, 24)` and `12` (SnackBar), `borderRadius: 16` (icon box), `width: 8, height: 8` (dots), `SizedBox(width: 6)`.

**Why it matters**  
A token scale that is overridden in a dozen places is documentation, not a system. Vertical rhythm never resolves to a common multiple, so gaps between cards (5+5=10), inside cards (18) and around the filter row (16/8) have no relationship. The 118px bottom padding is a magic number tuned to the 64px FAB by hand — any FAB change silently breaks the clearance.

**Fix**  
Strict 4pt base with an 8pt rhythm, no exceptions, and derive FAB clearance from the FAB token.

---

#### UI-15 — The capture input has no focus, filled or error state at all
- **Area:** Components
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
CaptureSheet's TextField uses `border: InputBorder.none` and a hintText, with no `focusedBorder`, `errorText`, counter or `InputDecorationTheme` anywhere in the theme.

**Why it matters**  
Chromeless is the right call for capture — but the field then has no visual difference between focused-and-empty, focused-with-text, and blurred. On desktop, where multiple things can hold focus, there is no way to tell whether typing will go into the note. The add-tag dialog has the same problem plus no validation feedback: an empty submit silently closes.

**Fix**  
Keep the field chromeless but give it a live caret in the accent colour and an ink-line that animates in on focus. Add inline validation to the tag dialog.

---

#### UI-16 — The primary action of the entire product is an unlabelled plus button
- **Area:** Components
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
`FloatingActionButton(child: Icon(Icons.add, size: 32), tooltip: l10n.capture)` at 64×64, `centerFloat`, elevation 1.

**Why it matters**  
A tooltip is desktop-only; on touch it never appears. The single most important control communicates 'add something' generically, when the product's whole claim is that it is the fastest way to record a thought. There is also no distinction between the four capture types until the sheet opens.

**Fix**  
Make the mark a caret, not a plus, and give it an extended label on first run and on desktop.

---

#### UI-19 — Everything is a modal sheet, and sheets stack
- **Area:** IA
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
Capture, Note detail, Settings, Update, and the content-type picker are all `showModalBottomSheet`. Settings opens Update as a nested sheet and pushes Tag Manager and Recently Deleted as routes from inside a sheet. Search is the one full route push.

**Why it matters**  
There is no persistent chrome, so there is no way to move laterally: from Search you cannot reach Settings without dismissing back to the timeline. Modal depth of three (Settings → Tag Manager → dialog) on a bottom sheet is fragile on Android back-gesture and has no visible breadcrumb.

**Fix**  
Give the app one persistent navigation surface and reserve modals for genuinely transient tasks.

---

#### UI-20 — Search — a core promise of the product — costs a tap and a full-screen transition
- **Area:** IA
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
Timeline AppBar has `IconButton(Icons.search)` which does `Navigator.push(MaterialPageRoute(SearchScreen))`. SearchScreen has its own AppBar with an autofocused TextField.

**Why it matters**  
'Find in Seconds' is half the tagline. Making it a route push behind an unlabelled icon puts it one interaction and one 220ms transition further away than it needs to be, and the timeline itself has no query field at all.

**Fix**  
Put a real search field in the timeline header that expands in place.

---

#### UI-23 — No skeleton or loading affordance exists anywhere in the app
- **Area:** States
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
No `Shimmer`, no skeleton widget, and no `CircularProgressIndicator` outside update_sheet.dart. The bootstrap host renders a static `Text('Nex', fontSize: 34)`.

**Why it matters**  
Every async surface — timeline load, filter application, search, tag list, storage figures — transitions from stale content directly to new content with no indication that work is in flight. The launch screen is a static word with a `Semantics(label: 'Nex is opening')` that sighted users cannot perceive.

**Fix**  
One skeleton primitive, used on every async surface, plus a launch state that shows progress.

---

#### UI-24 — Error handling is a single generic SnackBar with no recovery path
- **Area:** States
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
`capturePhoto` wraps everything in `try/catch (_)` and shows `SnackBar(Text(l10n.captureFailed))`. The update sheet renders raw `'$error'` strings. No error surface offers a retry.

**Why it matters**  
Photo capture can fail for at least four distinct reasons — permission denied, storage full, unreadable file, database write failure — and all four produce the same sentence with no action. The user's only recourse is to guess and try again.

**Fix**  
Typed failures mapped to specific, localised, actionable messages with a retry affordance.

---

#### UI-27 — The desktop layout is one 760px column in an unbounded window, and the filter row is not aligned to it
- **Area:** Responsive
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
`Expanded(child: Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 760), child: ListView...)))` — but `TagFilterRow` is a sibling *above* that Center, so it spans the full window width. The FAB is `centerFloat`, centred on the window rather than the column.

**Why it matters**  
On a 1920px Windows window the content column occupies 40% of the width with the filter pills starting at the far-left window edge, visibly misaligned with the cards beneath them. There is no breakpoint system, no master–detail layout, and note detail still opens as a bottom sheet on a desktop monitor.

**Fix**  
A real breakpoint scale with a two-pane layout above 900px, and align every element to the same content column.

---

#### UI-29 — Screen-reader labels are hardcoded English in a bilingual app
- **Area:** A11y
- **Severity:** major
- **Confidence:** confirmed

**Evidence**  
note_card.dart builds `'${note.type.name} note'` and `'Tags: ${...}'` into the Semantics label. TagChip declares `Semantics(label: 'Accent color')`. The app ships full English and Farsi ARB localisations.

**Why it matters**  
A Farsi user running TalkBack hears 'text note. Tags: کار' — the structural words in English, the content in Farsi. The design-system package deliberately carries no localisations (TagFilterRow's `allLabel` is passed in from the app for exactly this reason), but the semantic strings were not given the same treatment.

**Fix**  
Pass semantic strings into the UI package the same way `allLabel` already is.

---

#### UI-05 — Destructive-swipe and validation-error share one colour
- **Area:** Colour
- **Severity:** minor
- **Confidence:** confirmed

**Evidence**  
`error: NexColors.swipeDelete` in the ColorScheme copyWith.

**Why it matters**  
Two different meanings — 'releasing will delete this' and 'this input is invalid' — are rendered identically. #C0392B is also a muted brick that reads more like a warning than a destructive confirmation.

**Fix**  
Separate `danger` (destructive intent) from `error` (invalid state) as distinct roles.

---

#### UI-06 — Comfort themes reuse the default border tokens, breaking the sepia cast
- **Area:** Colour
- **Severity:** minor
- **Confidence:** confirmed

**Evidence**  
`nexLightTheme(comfortMode: true)` passes `border: NexColors.borderLight` (#EBEAE8, a cool grey) onto a #F7F1E6 warm cream ground. Comfort dark passes #262626 onto #17130F.

**Why it matters**  
A cool hairline on a warm ground is visibly off-hue and undoes the point of the sepia mode.

**Fix**  
Give each theme its own border token derived from that theme's own ramp.

---

#### UI-10 — Tag pills bypass the text theme entirely
- **Area:** Type
- **Severity:** minor
- **Confidence:** confirmed

**Evidence**  
`_Pill` in tag_filter_row.dart uses `TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg)` — a raw inline TextStyle, not a theme lookup.

**Why it matters**  
The most-used control on the timeline is typeset outside the system. It will not respond to a scale change, and on Windows it inherits no font family from the theme's `fontFamily`, so the pills may render in a different face than the cards beside them.

**Fix**  
Route every text style through the theme. Lint against inline `TextStyle(fontSize:` in the UI package.

---

#### UI-12 — Four unrelated corner radii, none on a scale
- **Area:** Spacing
- **Severity:** minor
- **Confidence:** confirmed

**Evidence**  
cardRadius 22 (cards, SnackBar, empty-state ghosts), 16 (icon boxes, media thumbnails), StadiumBorder (filter pills, type button), and Material's InputChip default ~8 (tag chips).

**Why it matters**  
22 is not a step in any common radius scale, and a 22px outer radius wrapping a 16px inner radius at 18px inset produces a mismatched concentric curve (the correct inner radius for that inset would be 4). Two chip shapes — stadium in the filter row, rounded-rect in the card — represent the same object.

**Fix**  
One radius scale, one chip shape, and derive inner radii from outer minus inset.

---

#### UI-17 — No hover states and no elevation system for desktop
- **Area:** Components
- **Severity:** minor
- **Confidence:** confirmed

**Evidence**  
No `WidgetStateProperty` hover handling in any custom widget; no shadow tokens exist. The only elevations in the codebase are FAB `elevation: 1` and SnackBar `elevation: 6`.

**Why it matters**  
On Windows the pointer gets Material's default 8% onSurface overlay, which on a near-white surface with a near-black onSurface is a very faint grey — barely perceptible on the card, and on the stadium pills the ripple is clipped to a shape with no hover fill defined.

**Fix**  
Define a 5-step elevation scale and explicit hover/pressed overlays per component.

---

#### UI-21 — The anniversary feature renders as one line of unstyled grey text
- **Area:** IA
- **Severity:** minor
- **Confidence:** confirmed

**Evidence**  
In the ListView builder, index 0 when anniversary is non-empty returns `Padding(symmetric(horizontal: 20, vertical: 16), child: Text(l10n.oneYearAgo(n), style: bodySmall))`.

**Why it matters**  
A resurfacing feature — the single most valuable retention mechanism a capture app has — is a 12.5px grey sentence with no icon, no container, no affordance and no way to act on it. It also cannot be tapped: it is not wrapped in any gesture detector.

**Fix**  
Give it a distinct card treatment and make it actionable.

---

#### UI-25 — The 'note landed' animation never resets and is imperceptible
- **Area:** States
- **Severity:** minor
- **Confidence:** confirmed

**Evidence**  
`landedId` is set on commit and never cleared. `AnimatedSlide(offset: landedId == note.id ? Offset(0, -0.02) : Offset.zero)`.

**Why it matters**  
A 2% vertical offset on a ~90px card is under 2 logical pixels — below the threshold of perception for most people. And because `landedId` is never nulled, the last-captured note stays permanently nudged upward until the widget is rebuilt from scratch, so the state is a latent 2px misalignment rather than an animation.

**Fix**  
Replace with a deliberate, visible commit receipt that decays. Clear the id when it completes.

---

#### UI-26 — The in-app reduce-motion preference is not consulted at the animation call site
- **Area:** Motion
- **Severity:** minor
- **Confidence:** confirmed

**Evidence**  
`NexPreferences.reduceMotion` exists as a stored preference. The timeline's AnimatedSlide checks only `MediaQuery.disableAnimationsOf(context)`; the search screen's AnimatedSize does the same.

**Why it matters**  
A user who enables Reduce Motion inside Nex, without setting the OS-level flag, gets no change in behaviour at these two call sites — the only two animated surfaces in the app.

**Fix**  
Resolve motion duration through one helper that ORs the OS flag with the app preference.

---

#### UI-28 — Fixed 56px media thumbnails and 64px FAB do not scale with text size
- **Area:** Responsive
- **Severity:** minor
- **Confidence:** inferred

**Evidence**  
`_IconBox` and the photo thumbnail are hardcoded `width: 56, height: 56`; `nexCaptureFabSize = 64`. Text styles scale with the platform text-size setting; these do not.

**Why it matters**  
At 200% text scale the note preview text grows to roughly 32px while the icon beside it stays 56px, so the intended visual balance inverts and the card's leading column looks undersized. This is inferred — it follows from Flutter's scaling model rather than from an observed render.

**Fix**  
Scale container dimensions with `MediaQuery.textScalerOf` for elements paired with text.

---

#### UI-30 — `excludeSemantics: true` collapses each card into a single unnavigable label
- **Area:** A11y
- **Severity:** minor
- **Confidence:** confirmed

**Evidence**  
NoteCard wraps its content in `Semantics(button: true, label: _label(), excludeSemantics: true)`.

**Why it matters**  
The whole card becomes one string, so a screen-reader user cannot navigate to the date, to an individual tag, or to the preview text separately, and cannot act on a tag from the card. For a two-line preview plus several tags that is a long undifferentiated announcement.

**Fix**  
Keep the card as a semantic button but expose tags as child nodes rather than excluding them.

---

#### UI-31 — Bidirectional text is handled in the capture sheet but not in the card preview
- **Area:** A11y
- **Severity:** minor
- **Confidence:** inferred

**Evidence**  
CaptureSheet applies `nexTextDirection(controller.text)` and `nexTextAlign(...)` per-value. NoteCard's `_Preview` renders a plain `Text(text, maxLines: 2)` with no directionality override.

**Why it matters**  
A Farsi note typed correctly in the capture sheet will render left-aligned in the timeline card when the UI locale is English, and the ellipsis will truncate from the wrong end. Inferred from the asymmetry between the two call sites rather than observed.

**Fix**  
Apply the same per-value direction detection wherever user content is rendered.

---

#### UI-32 — Filled and outlined icons are mixed inside a single list, and one concept has two icons
- **Area:** Icons
- **Severity:** minor
- **Confidence:** confirmed

**Evidence**  
`_typeIcon` returns `Icons.all_inclusive` (filled), `Icons.short_text` (filled), `Icons.graphic_eq` (filled), `Icons.photo_outlined` (outlined), `Icons.insert_drive_file_outlined` (outlined) — three filled, two outlined, rendered as five rows of one picker. Separately, NoteCard's `_Leading` uses `Icons.image_outlined` for a photo note while `_typeIcon` uses `Icons.photo_outlined` for the same type. Across the app: `Icons.search` filled but `Icons.settings_outlined` outlined in the same AppBar.

**Why it matters**  
Weight inconsistency inside one list is immediately legible as unpolished, and two different glyphs for 'photo note' means the filter icon and the card icon do not visually correspond.

**Fix**  
Pick one weight, define an icon map as a single source of truth, and lint direct `Icons.` references in feature code.

---

### 1.2 Current Colour Palettes

**Light (default)** (background: `#FFFFFF`)

| Name | Token | Hex | Role | Contrast against | WCAG requires |
|---|---|---|---|---|---|
| Background | `bgPrimaryLight` | `#FFFFFF` | Scaffold + card fill | — | — |
| Elevated | `bgElevatedLight` | `#F5F4F2` | Icon box, surfaceContainerHighest | #FFFFFF | 3:1 |
| Text primary | `textPrimaryLight` | `#111113` | Body, titles, FAB fill | #FFFFFF | 4.5:1 |
| Text secondary | `textSecondaryLight` | `#68686D` | Dates, captions, bodySmall | #FFFFFF | 4.5:1 |
| Border | `borderLight` | `#EBEAE8` | Card outline, dividers | #FFFFFF | 3:1 |

**Dark (default)** (background: `#0A0A0A`)

| Name | Token | Hex | Role | Contrast against | WCAG requires |
|---|---|---|---|---|---|
| Background | `bgPrimaryDark` | `#0A0A0A` | Scaffold + card fill | — | — |
| Elevated | `bgElevatedDark` | `#171717` | Icon box | #0A0A0A | 3:1 |
| Text primary | `textPrimaryDark` | `#FAFAFA` | Body, titles | #0A0A0A | 4.5:1 |
| Text secondary | `textSecondaryDark` | `#A3A3A3` | Dates, captions | #0A0A0A | 4.5:1 |
| Border | `borderDark` | `#262626` | Card outline | #0A0A0A | 3:1 |

**Comfort light (sepia)** (background: `#F7F1E6`)

| Name | Token | Hex | Role | Contrast against | WCAG requires |
|---|---|---|---|---|---|
| Background | `bgPrimaryLightComfort` | `#F7F1E6` | Scaffold + card fill | — | — |
| Elevated | `(inline)` | `#F0E8DA` | Icon box | #F7F1E6 | 3:1 |
| Text primary | `textPrimaryLightComfort` | `#2E2A22` | Body, titles | #F7F1E6 | 4.5:1 |
| Text secondary | `textSecondaryLightComfort` | `#625E56` | Captions | #F7F1E6 | 4.5:1 |
| Border | `borderLight (reused)` | `#EBEAE8` | Card outline | #F7F1E6 | 3:1 |

**Comfort dark (sepia)** (background: `#17130F`)

| Name | Token | Hex | Role | Contrast against | WCAG requires |
|---|---|---|---|---|---|
| Background | `bgPrimaryDarkComfort` | `#17130F` | Scaffold + card fill | — | — |
| Elevated | `(inline)` | `#1F1A15` | Icon box | #17130F | 3:1 |
| Text primary | `textPrimaryDarkComfort` | `#D9CFC0` | Body, titles | #17130F | 4.5:1 |
| Text secondary | `textSecondaryDarkComfort` | `#AAA094` | Captions | #17130F | 4.5:1 |
| Border | `borderDark (reused)` | `#262626` | Card outline | #17130F | 3:1 |

**Action colours (theme-independent)** (background: `#FFFFFF`)

| Name | Token | Hex | Role | Contrast against | WCAG requires |
|---|---|---|---|---|---|
| Swipe delete | `swipeDelete` | `#C0392B` | Delete panel + ColorScheme.error | #FFFFFF | 4.5:1 |
| Swipe add-tag | `swipeAddTag` | `#4A5568` | Add-tag panel | #FFFFFF | 4.5:1 |

### 1.3 Current Typography

**Defined styles:**

| Style | Size | Weight | Line height | Colour | Used for |
|---|---|---|---|---|---|
| displaySmall | 30 | 600 | 1.18 | primary | Empty-state promise line |
| titleLarge | 22 | 600 | 1.4 | primary | Sheet titles |
| titleMedium | 17 | 600 | 1.4 | primary | Section heads, zero-results |
| bodyLarge | 16 | 400 | 1.5 | primary | Note preview text |
| bodyMedium | 14 | 400 | 1.5 | primary | Supporting copy |
| bodySmall | 12.5 | 500 | 1.4 | secondary | Dates, tags, footnotes, storage |

**Missing Material type-scale roles (undefined, falling back to defaults):**
- `displayLarge`
- `displayMedium`
- `headlineLarge`
- `headlineMedium`
- `headlineSmall`
- `titleSmall`
- `labelLarge`
- `labelMedium`
- `labelSmall`

---

## 2. Redesign Proposal

### 2.1 Brand Thesis

**Ink & Signal** — Warm graphite paper, one rationed accent that means the app is live.

The current design is a competent greyscale minimalism that reads as absence-of-decision rather than decision. The redesign keeps the restraint and adds an argument: the interface is warm neutral paper, and colour appears only where Nex is actively doing something — the caret, the recording pulse, the focus ring, the active filter, the commit receipt. Colour becomes information rather than decoration, which is a stronger form of minimalism than having no colour at all, and it gives the product something ownable. Nobody in this category owns burnt amber, and nobody uses a caret as their mark.

**Pillars:**

- **Paper, not canvas** — Neutrals carry a warm cast (hue ≈ 45°) rather than pure grey. Pure #FFFFFF and #0A0A0A are harsh on OLED and clinical in daylight; a warm ramp reads as paper and makes the sepia comfort mode a variation of the identity rather than a separate theme.
- **Ember means live** — One accent, spent only on: the capture caret, recording state, focus rings, the active filter pill, and the commit receipt. If Ember is on screen, Nex is doing something. This makes the accent load-bearing and keeps the rest of the surface silent.
- **The caret is the mark** — The logo, the FAB glyph and the launch animation are all the same object: a vertical caret. It says 'start typing' with no words, works as a monochrome silhouette for the themed Android icon, and animates naturally into the composer.
- **Metadata is monospaced** — Timestamps, durations, byte counts and version numbers set in a tabular mono. Small craft signal, aligns numerals in columns, and makes the timeline read as a log — which is exactly what it is.

### 2.2 New Colour System

**Ink — warm graphite neutrals**  
Hue ≈ 45°, chroma tapering to near-zero at the extremes. Every surface, border, and text colour is drawn from this one ramp so tonal relationships are predictable.

| Step | Hex | Note |
|---|---|---|
| 50 | `#FAF9F7` | Card / paper surface (light) |
| 100 | `#F4F2EE` | Page ground (light) |
| 200 | `#E8E4DE` | Hairline dividers |
| 300 | `#D6D1C8` | Decorative borders |
| 400 | `#A8A196` | Disabled text, icon strokes |
| 500 | `#7C756A` | Meaningful borders (4.33:1) |
| 600 | `#5C554B` | Secondary text (6.99:1) |
| 700 | `#403A32` | Body text on light |
| 800 | `#2A251F` | Card surface (dark) |
| 900 | `#1A1611` | Page ground (dark) |
| 950 | `#0F0E0C` | Deepest ground (OLED) |

**Ember — the signal accent**  
A burnt amber. Warm enough to sit inside the Ink ramp without clashing, saturated enough to read as 'live' at 2px. Rationed to capture, focus, recording and active state — never used decoratively.

| Step | Hex | Note |
|---|---|---|
| 300 | `#FDBA74` | Subtle fills on dark |
| 400 | `#FB923C` | Accent text on dark (8.5:1) |
| 500 | `#EA580C` | Focus rings, caret, large accents |
| 600 | `#C2410C` | Filled buttons w/ white text (5.2:1) |
| 700 | `#9A3412` | Pressed state |

**Semantic — separated by meaning**  
Destructive intent and invalid state are split into distinct roles, and success gets its own colour so a commit receipt does not have to borrow the accent.

| Step | Hex | Note |
|---|---|---|
| danger | `#B42318` | Destructive swipe + confirm |
| error | `#D92D20` | Invalid input state |
| success | `#067647` | Sync complete, restore done |
| info | `#175CD3` | Neutral system notices |
| organise | `#5C554B` | Add-tag swipe (Ink 600) |

### 2.3 New Typography System

**Fonts:**

| Role | Family | Weights | Rationale |
|---|---|---|---|
| Display | Instrument Serif | 400 | Used only for the empty-state promise, the About header and the wordmark. An editorial serif at large sizes gives the product a voice in the two or three moments it actually speaks, and it is what makes the identity memorable rather than generic. Open-licensed, ~40 KB subset. |
| Interface | Inter Variable | 400 / 500 / 600 | Everything else. Designed for screen UI at small sizes, has genuine optical sizing, and — critically — replaces the current three-different-typefaces-per-platform situation with one face everywhere. Variable so all three weights cost one file. |
| Metadata | JetBrains Mono | 400 / 500 | Timestamps, durations, byte counts, version strings. Tabular figures align in a scrolling list, and the mono texture visually separates machine-generated metadata from human-written content. |
| Farsi | Vazirmatn Variable | 400 / 500 / 600 | Swapped in for the `fa` locale. Metric-compatible with Inter's x-height so mixed-script lines do not jump, variable, and far better-drawn than the Arabic fallbacks the platforms supply by default. |

**Type scale:**

| Token | Size | Line height | Weight | Family | Use |
|---|---|---|---|---|---|
| display-lg | 40 | 44 | 400 | Instrument Serif | Empty-state promise |
| display | 32 | 38 | 400 | Instrument Serif | About, first-run |
| title-lg | 24 | 32 | 600 | Inter | Sheet titles |
| title | 20 | 28 | 600 | Inter | Section headers |
| title-sm | 17 | 24 | 600 | Inter | List group headers |
| body-lg | 17 | 26 | 400 | Inter | Note body + preview |
| body | 15 | 22 | 400 | Inter | Supporting copy |
| label | 14 | 20 | 500 | Inter | Buttons, chips, pills |
| caption | 13 | 18 | 500 | Inter | Helper text |
| meta | 12 | 16 | 500 | JetBrains Mono | Timestamps, sizes |

### 2.4 Spacing, Radius, Elevation & Motion

**Base rhythm:** 4pt base unit, 8pt rhythm. Ten steps, no exceptions, no inline values.

**Spacing steps:**

| Token | px |
|---|---|
| space-0 | 0 |
| space-1 | 4 |
| space-2 | 8 |
| space-3 | 12 |
| space-4 | 16 |
| space-5 | 20 |
| space-6 | 24 |
| space-8 | 32 |
| space-10 | 40 |
| space-12 | 48 |
| space-16 | 64 |

**Radii:**

| Token | px | Use |
|---|---|---|
| radius-xs | 4 | Accent dots, tiny marks |
| radius-sm | 8 | Inputs, small buttons |
| radius-md | 12 | Buttons, media thumbnails |
| radius-lg | 20 | Cards, SnackBar |
| radius-xl | 28 | Bottom sheets (top corners) |
| radius-full | 999 | Pills, chips, FAB |

**Elevation (light):**

| Token | CSS | Use |
|---|---|---|
| e0 | `none` | Flat + border only |
| e1 | `0 1px 2px rgba(26,22,17,.06), 0 1px 1px rgba(26,22,17,.04)` | Cards at rest |
| e2 | `0 2px 8px rgba(26,22,17,.08), 0 1px 2px rgba(26,22,17,.06)` | Card hover |
| e3 | `0 8px 24px rgba(26,22,17,.12), 0 2px 6px rgba(26,22,17,.08)` | FAB, sheets |
| e4 | `0 16px 48px rgba(26,22,17,.16)` | Dialogs |

**Elevation (dark):** Shadows are invisible on near-black. In dark mode each elevation step instead lightens the surface: e1 = Ink 800, e2 = +3% white, e3 = +6%, e4 = +9%, paired with a 1px Ink 700 border.

**Motion:**

| Token | ms | Curve | Use |
|---|---|---|---|
| instant | 100 | `linear` | State flips, checkbox |
| fast | 160 | `cubic-bezier(.2,0,0,1)` | Hover, press, ripple |
| base | 220 | `cubic-bezier(.2,0,0,1)` | Sheets, page transitions |
| slow | 320 | `cubic-bezier(.2,0,0,1)` | Shared-element, expand |
| receipt | 600 | `cubic-bezier(.4,0,.2,1)` | Commit-receipt decay |

### 2.5 Component Specs

#### Buttons

**Before:**  
Three implicit variants inherited from Material with no state definitions. FilledButton resolves to near-black-on-white. No hover, no focus ring, no loading state, no disabled treatment beyond Material's default 38% opacity. `labelLarge` is undefined so button text comes from Material's default typography.

**After:**  
Five explicit variants × six states, all tokenised. Sizes: lg 48px, md 40px, sm 32px — each padded to a 48px minimum hit area regardless of visual height. Label always `label` (Inter 14/500). Radius `radius-md`. Icon-only buttons are 40×40 visual, 48×48 target.

**States:**

| State | Spec |
|---|---|
| Default | Primary: Ember 600 fill, #FFF label. Secondary: transparent, 1px Ink 500 border, Ink 700 label. Tertiary: transparent, Ink 600 label. |
| Hover | Primary → Ember 700. Secondary → Ink 100 fill. Tertiary → Ink 100 fill. Plus e1 on primary. |
| Pressed | Scale 0.98, elevation drops to e0, 160ms. Primary → Ember 700 with a 12% Ink overlay. |
| Focus | 2px Ember 500 ring at 2px offset, on every variant, in addition to the hover treatment. Never removed. |
| Disabled | Ink 200 fill, Ink 400 label, no border, cursor not-allowed. Never below 3:1 for the label. |
| Loading | Label swaps for a 16px indeterminate spinner in the label colour; width is locked to prevent reflow. |

#### Text inputs

**Before:**  
Capture field is `InputBorder.none` with a hint and nothing else — no focus, filled, or error state. The add-tag dialog is a bare TextField with a hint, no validation, no counter; submitting empty silently dismisses. No InputDecorationTheme exists in the app.

**After:**  
Two archetypes. **Chromeless (capture)** keeps zero border but gains an Ember 500 caret at 2px, and a 1px Ink 200 ink-line beneath the field that wipes to Ember 500 over 160ms on focus — enough to confirm where keystrokes go without adding a box. **Framed (all other fields)** is a 44px field, Ink 50 fill, 1px Ink 300 border, radius-sm.

**States:**

| State | Spec |
|---|---|
| Rest | Ink 50 fill, 1px Ink 300 border, Ink 400 placeholder. |
| Hover | Border → Ink 400. |
| Focus | Border → Ember 500 at 2px, plus a 3px Ember 500 @ 12% halo. Caret Ember 500. |
| Filled | Border Ink 300, text Ink 800, clear-affordance appears at the trailing edge. |
| Error | Border → error #D92D20 at 2px, 13px error message below with a 16px alert glyph, live-region announced. |
| Disabled | Ink 100 fill, Ink 200 border, Ink 400 text. |

**Notes:**  
["The add-tag dialog gains inline validation: empty is blocked with a message rather than silently dismissing, duplicates surface 'already on this note', and a 32-character counter appears past 24 characters."]

#### Note card

**Before:**  
White fill on white page with a 1.20:1 hairline. 22px radius wrapping 16px inner radii at 18px inset. 56px icon box at 1.10:1 against the card. Outer padding `symmetric(horizontal: 16, vertical: 5)`. Date and tags share one Wrap at `spacing: 6, runSpacing: 5`. No hover, no focus, no pressed state.

**After:**  
Paper-on-desk: Ink 50 card on an Ink 100 page (a real tonal step), 1px Ink 200 border, e1 shadow, radius-lg 20. Inset space-4 (16), inner radius 12 to sit concentrically. Leading slot becomes a 44px typed glyph on an Ink 100 disc with a 1px Ink 200 ring — visible at 1.9:1 — or the media thumbnail at radius-md. Metadata row uses `meta` mono for the timestamp, then tag chips. Gap between cards space-2 (8), uniform.

**States:**

| State | Spec |
|---|---|
| Rest | e1, 1px Ink 200. |
| Hover | e2, border → Ink 300, 160ms. Desktop only. |
| Pressed | Scale 0.99, e0, 100ms. |
| Focus | 2px Ember 500 ring at 2px offset. |
| Just committed | 3px Ember 500 bar on the leading edge, fading to transparent over 600ms — a visible receipt replacing the missing Save button. |
| Swipe reveal | Panel colour resolves at 35% threshold; icon and label cross-fade in at 20%; haptic at the threshold. |

#### Filter pills & tag chips

**Before:**  
Two shapes for one object: stadium `_Pill` in the filter row (34px tall, inline TextStyle, 15/8 padding) and Material `InputChip` with `visualDensity: compact` on cards (~24–28px). The type-filter button is 32px. All three are below the project's own 44px token.

**After:**  
One chip primitive, radius-full, 32px visual height with 48px hit area via transparent padding, `label` typography from the theme. Accent dot 8px at radius-full, or omitted when the tag has no colour — the current code substitutes a grey dot for uncoloured tags, which reads as a broken swatch.

**States:**

| State | Spec |
|---|---|
| Rest | Ink 50 fill, 1px Ink 300 border, Ink 700 label. |
| Hover | Ink 100 fill, border Ink 400. |
| Selected | Ember 500 @ 12% fill, 1px Ember 500 border, Ember 700 label (light) / Ember 300 (dark). Colour now signals active state rather than inverting to black. |
| Focus | 2px Ember 500 ring, 2px offset. |
| Removable | Trailing 16px × glyph in a 24px target, appearing on hover/focus and always present on touch. |

#### Capture control

**Before:**  
64×64 FAB, `Icons.add` at 32px, centerFloat, elevation 1, tooltip only. No label on touch.

**After:**  
56×56 on mobile, radius-full, Ember 600 fill, e3. Glyph is the **caret mark**, not a plus — a 2px vertical bar with a subtle 1.2s blink at 30% opacity when the timeline has been idle for 5 seconds, which reads as 'ready for input'. First run and desktop show the extended form with a 'Capture' label. Long-press opens the four-way type radial (text / voice / photo / file) so the capture type is one gesture rather than a sheet.

**States:**

| State | Spec |
|---|---|
| Rest | Ember 600, e3, caret static. |
| Idle > 5s | Caret blinks at 1.2s, 30% → 100%, respecting reduce-motion. |
| Hover | Ember 500, e4, scale 1.04. |
| Pressed | Scale 0.96, e2, spring back over 220ms. |
| Recording | Morphs to a stadium with a live waveform and an Ember 500 pulse ring at 1s. |

#### Navigation shell

**Before:**  
No persistent chrome. Timeline is the only root; Search is a route push behind an icon; Settings, Capture, Note detail and Update are modal sheets; Tag Manager and Recently Deleted are routes reached from inside the Settings sheet.

**After:**  
See the IA section — a single-surface model on mobile with a persistent header search field and a Library sheet, and a persistent 240px rail on desktop with a two-pane list/detail layout above 900px.

#### Sheets & dialogs

**Before:**  
`showModalBottomSheet` with `showDragHandle: true` and Material defaults. Sheets nest up to three deep. No max width, so on a 1920px desktop window a sheet spans the entire screen.

**After:**  
radius-xl 28 top corners, e4, Ink 50 surface, 1px Ink 200 top border. Max width 560px, centred on desktop. Drag handle is Ink 300, 32×4, radius-full. Scrim Ink 950 @ 40% with a 4px backdrop blur. **Depth is capped at one**: any sheet that needs to open another surface pushes a route instead, with a back affordance in the sheet header.

#### Empty, loading & error states

**Before:**  
One empty state that doubles as onboarding and flashes on every cold launch. No skeletons anywhere. Errors are a single generic SnackBar. The launch screen is a static word.

**After:**  
Tri-state everywhere: **loading** renders a skeleton (three card shells, Ink 100 fill, 1.4s shimmer at 8% — disabled under reduce-motion, which switches to a static 60% opacity), **empty** renders the onboarding, **error** renders an inline panel with a specific message and a retry button. Distinct empty illustrations per surface: timeline (onboarding), search zero-results (with the nearest-miss card, which already exists), filtered-empty ('no notes with #work' + clear-filter action), and trash-empty.

### 2.6 Information Architecture

**Problem**  
Trash and Tag Manager — both content surfaces — live inside Settings. Search is a route push behind an unlabelled icon. Everything else is a modal sheet, and sheets nest three deep. There is no lateral movement: from Search you cannot reach anything without backing out first.

**Option A — Conventional bottom navigation**  
Three tabs (Now / Find / Library) with a docked centre FAB. Instantly familiar, solves discoverability outright, and gives every surface a permanent home.

Pros:
- Zero learning cost
- Trash and tags become obvious
- Lateral movement is free
Cons:
- Adds permanent chrome to a product whose thesis is getting out of the way
- A tab bar implies destinations, and the product's position is that there is one timeline
- Costs 56px of vertical space on the capture surface

*Verdict:* Rejected — it solves the IA problem by contradicting the product thesis.

**Option B — Single surface, promoted affordances (recommended)**  
Keep one root. Promote the buried surfaces into the timeline's own chrome instead of into a tab bar.

Changes:
- **Header becomes a live search field**, not an icon. Tapping expands it in place with results replacing the timeline — no route push, no transition, and 'Find in seconds' becomes literally true.
- **A Library sheet** replaces the type-picker button on the filter row and holds tags, note types, Recently Deleted and the anniversary feed. One tap from the timeline, and every content surface lives together.
- **Settings keeps the gear** and holds only preferences — appearance, capture, AI, sync, backup, about, update. Nothing that contains notes.
- **Modal depth capped at one.** Settings → Tag Manager becomes a route push with a back arrow, not a sheet on a sheet.
- **Note detail becomes a route on mobile** and the right pane on desktop, so it has a real back stack and can be deep-linked.

*Verdict:* Recommended. It fixes discoverability without adding permanent chrome, and it makes search a first-class surface rather than a detour.

**Desktop — a real layout, not a centred column**  
Above 900px the app becomes a 240px navigation rail + a 400px list column + a flexible detail pane. Above 1440px the detail pane caps at 720px and the whole assembly centres. The rail holds Timeline / Search / Library / Settings, so desktop gets persistent navigation without imposing it on mobile. Global hotkey (Ctrl+Alt+N) opens a frameless composer; Ctrl+K focuses search; Escape closes the topmost surface.

**Breakpoints:**

| Name | Range | Layout |
|---|---|---|
| compact | < 600px | Single column, FAB, sheets |
| medium | 600–899px | Single column max 600px, sheets max 560px |
| expanded | 900–1439px | Rail + list + detail pane |
| large | ≥ 1440px | Rail + list + detail, capped and centred |

### 2.7 Signature Ideas

**The commit receipt**  
The product's boldest claim is that there is no Save button. Right now nothing confirms a note was written — the 'landed' animation is a 2px nudge that never resets. Replace it with a 3px Ember bar on the card's leading edge that decays to transparent over 600ms. It is the visual equivalent of ink drying: unmistakable, non-blocking, and it appears exactly once per capture.

**The time gutter**  
Instead of date headers that interrupt the list, run a 32px left gutter down the timeline with hairline month markers and mono labels rotated to read vertically. Scrolling feels like moving through a continuous record rather than a series of grouped sections, and it gives the timeline a distinctive silhouette in a screenshot.

**Paper grain**  
A 2% procedural noise overlay on comfort-mode surfaces only. Almost subliminal, costs one shader, and it makes the sepia theme feel like a material rather than a beige rectangle. It is the kind of detail that gets a product noticed in a review.

**The caret that never stops**  
The launch screen is the caret, blinking. It does not fade out — it travels to the composer's first character position and becomes the actual text cursor. Launch and first-use are one continuous gesture, and the app appears to be already waiting rather than starting up.

**Tag colour as the only user-authored chroma**  
Since Ember is reserved for system state, user tag colours become the only other colour on screen — which makes them genuinely meaningful. Constrain the palette to eight hand-picked hues drawn at the same lightness as Ink 600 so any tag colour is legible on any surface, instead of the current free-form hex that can produce unreadable chips.

**Density as a first-class setting**  
Comfort mode currently only changes colour. Make it change density too: Comfortable (17px body, 20px inset, 2-line preview), Compact (15px body, 16px inset, 1-line), and Dense (15px body, 12px inset, no preview — timestamp and first line only). A 10,000-note library needs a different information density than a 50-note one.

### 2.8 Before / After Summary

| Metric | Before | After | Delta |
|---|---|---|---|
| Typefaces across platforms | 3 (Roboto / SF Pro / Segoe UI Variable) | 1 (Inter) + 1 display + 1 mono | good |
| Defined text styles | 6 of 15 | 10 of 10 (full custom scale) | good |
| Card boundary contrast | 1.20:1 — fails 1.4.11 | Tonal step + 1px Ink 200 + e1 | good |
| Icon container contrast | 1.10:1 — invisible | 1.9:1 disc + ring | good |
| Smallest tap target | 32px (type filter) | 48px hit area everywhere | good |
| Focus indicators | None (16% fill tint) | 2px Ember ring, 2px offset | good |
| Off-grid spacing values | 14, 18 + 11 hardcoded inline | 0 — strict 4pt scale | good |
| Corner radii in use | 4 unrelated (22/16/stadium/8) | 6-step scale, concentric | good |
| Accent colours | 0 (greyscale + 2 swipe colours) | 1 rationed signal (Ember) | good |
| Elevation tokens | 0 (two inline values) | 5 steps + dark-mode equivalent | good |
| Loading states | 0 | Skeleton primitive on every async surface | good |
| Empty-state flash on launch | Every cold start | Tri-state; skeleton first | good |
| Content surfaces in Settings | 2 (Trash, Tags) | 0 — moved to Library | good |
| Max modal depth | 3 | 1 | good |
| Desktop layout | 760px column, misaligned filter row | Rail + list + detail, 4 breakpoints | good |
| Localised screen-reader labels | No (hardcoded English) | Yes, injected like allLabel | good |

### 2.9 Rollout Plan

**Sprint 1 — Token foundation — no visual change shipped**
- Style Dictionary pipeline: tokens.json → Dart, Kotlin, Swift, CSS
- Full explicit ColorScheme replacing fromSeed; all 4 themes rebuilt on the Ink ramp
- Complete 10-step type scale; ship Inter + Instrument Serif + JetBrains Mono + Vazirmatn as assets
- Spacing, radius, elevation and motion tokens; lint rule banning inline TextStyle and raw EdgeInsets in packages/ui

**Sprint 2 — Accessibility floor**
- 48px hit areas on every interactive element
- Focus ring token wired through every custom widget via FocusableActionDetector
- Card, icon-box and border contrast raised past 3:1
- Semantic strings injected into packages/ui; bidi handling in NoteCard preview
- Golden tests at 1.0× / 1.5× / 2.0× text scale, light/dark/comfort, LTR and RTL

**Sprint 3 — Component rebuild**
- Button, input, chip, card, sheet primitives with full state matrices
- Skeleton primitive + tri-state on timeline, search, tags, storage
- Typed error states with retry
- Commit receipt replacing the AnimatedSlide nudge

**Sprint 4 — IA and layout**
- Header search field; Library sheet; Trash and Tags out of Settings
- Modal depth capped at 1; note detail becomes a route
- Breakpoint system + desktop rail and two-pane layout
- Global hotkeys and desktop keyboard map

**Sprint 5 — Identity and signature**
- Caret mark: app icon, themed monochrome icon, FAB glyph, launch animation
- Time gutter, paper grain, constrained tag palette
- Density modes
- Motion spec applied end to end; reduce-motion resolved through one helper
