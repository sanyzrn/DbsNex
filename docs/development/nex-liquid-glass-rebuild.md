# Liquid Glass — rebuilt from the films up (Nex 2.6.21)

> Scope: the whole Liquid Glass system, line by line — the token layer
> (`nex_appearance.dart`, `nex_tokens.dart`), every surface that draws the
> material (bar, dock, menus, dialogs, sheets, panels, pills), the client
> wiring (appearance mode, preferences, settings, theme assembly), and the
> tests that hold the material's floors — against `main` at `b85e624d`
> (PR #435, Nex 2.6.20). The feature shipped disabled
> (`nexLiquidGlassAvailable = false`); this review rebuilt it and switched
> it back on as a fresh opt-in.

## What was wrong

Six root findings, each verified in the tree before anything was changed:

1. **The top glass bar never drew.** `NexGlassBar`'s innermost child is a
   childless `DecoratedBox`, so nothing in it has a size of its own — and an
   `AppBar` hands its `flexibleSpace` *loose* constraints (it is laid out
   under an `Align` inside a `Stack(fit: StackFit.passthrough)`), so the
   whole bar collapsed to **390×0**. Measured, not guessed: the render box
   reported `Size(390.0, 0.0)` under a real `NexAppBar`. In glass mode the
   title and actions therefore sat straight on the scrolling notes with no
   bar at all — the single loudest way the look read as "incomplete", and
   no test could see it because a zero-height `BackdropFilter` still exists
   as a widget and still counts.

2. **The material was fog, not glass.** The washes transmitted a fifth or
   less of the backdrop's range (light panel 18.8%, dark panel 13.3%), so
   a coloured note behind a pane did not read as colour under glass. The
   2.6.20 tuning had fixed legibility by making the films heavier — the
   exact trade the file's own comments warn turns glass into "a painted
   panel wearing a blur".

3. **Dark glass was invisible on the page the app actually ships.** The
   visibility floor ("a panel can be seen against the page it floats on",
   ≥ 1.08:1) was only ever tested against the *classic* dark page. On the
   Soft Dark page (`#141821`) the 2.6.20 panel measured **1.044:1** —
   under the floor, on the default dark theme, with nothing but a hairline
   saving it. The legibility matrix had the same gap: Soft Dark and OLED
   Night were never in it.

4. **No light direction anywhere.** A hairline, a rim and a 5% shadow make
   a shape; nothing in the material said a light was *on* it. On the plain
   background — the default, because patterns are a separate paused opt-in
   — there is nothing behind the blur to reveal, so a pane was a translucent
   rectangle: correct by every measured floor and dead on the screen.

5. **`NexGlassWash.lerp` crashed on unequal film counts.** It indexed
   `other.films[i]` with `films.length` as the bound. Nothing ships unequal
   counts today, but the preset layer hand-builds washes and themes lerp
   live during a switch — a generation change would have thrown mid-fade.

6. **The disabled switch still carried its retirement scaffolding** — the
   "Temporarily unavailable" branch in Settings, the paused-flag assertions
   in three tests, and a v2 preference key whose saved `true` would have
   silently switched a materially different look on for anyone who had
   toggled it before the pause.

## What changed

### The films (`nex_tokens.dart`)

Every wash was re-solved, not adjusted. A grid search over the film stacks
enumerated candidates against **all** the floors the tests assert — body ink
on the worst of nine backdrops (black, dark page, dark card, mid grey, the
accent, danger, light page, comfort page, white), floating ink on its worst
ground including the optical gradient, the floating:panel transmission ratio
(> 1.35×), and panel-vs-page separation — for every theme the app ships,
including the two dark ones that were missing. The winners:

| Wash | 2.6.20 | 2.6.21 | Notes |
| --- | --- | --- | --- |
| Light panel | 19% | **27%** | worst ink 6.0:1 (floor 4.9) |
| Comfort panel | ~18% | **23%** | warm ink `#2E2A22` — the binding constraint the old search missed |
| Dark panel | 13% | **20%** | sep vs Soft Dark page 1.04 → **1.11**; vs OLED 1.19 → **1.25** |
| Light floating | ~27% | **37%** | ratio 1.38×; ground ink 4.73 (classic) |
| Dark floating | ~29% | **29%** | ground ink 4.55 → **4.76** (soft ink, the stricter one) |

The dark anchor moved from neutral `#262626` to the blue-grey `#2C313E`, one
step into the Soft Dark page's own cast and lighter — elevation in a dark
theme has to be a lighter tone, not a border. The comfort stack carries its
warm anchor harder than the plain one because the comfort *ink* is lighter
than the plain theme's; that ink was the bug behind the first failed
candidate (4.467 against a 4.5 floor).

The blur moved with the transmission: **sigma 10 → 12**, so the extra
backdrop the films now let through arrives pre-smeared. A glyph stroke still
lands across six times its own width.

### The optics (`nex_appearance.dart`)

`NexGlassSurface`'s rim painter became `_GlassOpticsPainter`: the hairline
gradient stroke it always had, plus two new inner strokes — a **specular**
fading down from the top curve and a **shade** rising from the bottom, each
clipped to its own end of the pane with its gradient landing on zero exactly
at the clip so the two halves meet without a seam. All source-over: the
"first paint of a sliver reads an empty layer" lesson from the additive and
luminosity experiment stays honoured — no stroke in the material reads the
destination. New `NexVisualStyle` fields `glassSpecular` (white at 85% light
/ 40% dark) and `glassShade` carry them, lerped and copied like every other
token.

`NexGlassBar` gained the same lit line along its bottom edge (the one edge
that faces the content) and — the point of fix 1 — a `SizedBox.expand` so it
fills the slot it is handed. Verified in pixels: the bar band now reads
(220,222,224) over the white page, (39,42,49)→(30,33,40) over Soft Dark with
its vertical gradient, and the dock's top edge peaks at (115,116,118)
against an interior of (15,16,19) — a real catch-light in the darkest theme.

The pane's optical gradient gained a direction: a bright band across the
top-left 18%, a clear reading band through the middle, depth gathering
toward the bottom-right corner, instead of the single long ramp that tinted
the pane evenly.

### The client wiring

- `nexLiquidGlassAvailable` is `true`. The Settings row is a live switch
  again; the "Temporarily unavailable" branch is gone.
- The preference moved to `appearance.liquid_glass_v3`, exactly as each
  generation before it moved its key: a `true` saved under v2 (or v1) is
  kept on disk and not honoured, so nobody gets a materially different look
  switched on by a stored bit from a look they never saw. The switch writes
  only the current key.
- The still preset zeroes the new optics along with the rest of the glass
  tokens, so a preset whose point is "nothing decorative" stays that way.
- `NexGlassWash.lerp` holds the last film of a shorter stack instead of
  throwing.

## Tests

- **New:** the bar fills its slot (the zero-height regression, held by
  render-box size against the AppBar's own); the pane carries a lit and a
  shaded edge in every glass theme and survives copyWith/lerp; a wash lerps
  across unequal film counts; the transmission floors above, so a future
  tuning cannot quietly go back to fog; a real-app glass build in all three
  shipped appearances (`glass_capture_test.dart`, which doubles as the
  capture tool: `flutter test --dart-define=NEX_GLASS_CAPTURE=<dir> ...`).
- **Extended:** the legibility matrix now includes `nexSoftDarkTheme` and
  `nexOledNightTheme`; the panel-vs-page visibility test now checks all five
  shipped pages rather than the classic pair (this is the test that would
  have caught finding 3).
- **Updated to the enabled world:** the three paused-behaviour tests —
  appearance modes (a stored v2 choice does not enable the material; a live
  toggle reaches both themes), the dock (glass on means the dock draws the
  floating material, transmission and specular present), and the theme
  reveal (toggling glass runs the reveal and settles).
- **Re-run whole:** `packages/ui` 373, `apps/client` 2059 top-level + 1166
  module/performance, `packages/core` 283, `packages/data` 366 (+14 skips),
  `packages/ai` 258. `flutter analyze --fatal-infos` clean in `ui` and
  `client`; `dart format` clean on every changed file.

## Limitations

- The washes remain four flat source-over films. True vibrancy (a saturation
  boost of the backdrop itself) needs destination-reading blend modes, which
  this codebase tried and reverted: during a refresh or a sliver's first
  paint the destination can be an empty layer and the panels went grey. The
  extra transmission here is the safe fraction of the same effect.
- Edge *refraction* — the backdrop bending at a pane's rounded corner, the
  other half of Apple's look — needs backdrop sampling with displacement,
  which `BackdropFilter`'s `ImageFilter` set does not offer on stable. The
  specular and shade strokes are the honest approximation available.
- The pixel-level verification runs on the test rasteriser and the numeric
  floors on the compositor model; neither replaces a phone screen. The
  capture tool above exists for exactly that look-before-ship moment.
- `nexApplyThemePreset`'s per-preset wash override still builds 2.6.18-era
  stacks for the paused gallery. It compiles and stays unused while presets
  are off; re-tuning it is part of re-enabling the gallery, not of this
  change.

## Risks

- **Backdrop blur cost is unchanged in count** — the bar, the dock, open
  menus, sheets and dialogs each keep exactly one `BackdropFilter`, and the
  bar's goes from never-drawing (0 px) to real work. Devices that ran glass
  in 2.6.18 will see the bar's blur for the first time; that is the cost of
  the bar existing, and it is the same layer the dock already paid.
- **The dark glass is lighter than before** by design (elevation). Anyone
  who had memorised the old near-invisible dark panel will see a new tone;
  the legibility floors held it at ≥ 5.9:1 worst-case, so the change is
  presence, not noise.
- **Nobody is opted in automatically.** The worst-case risk of the rebuild
  is a user who never touches the switch: for them the app is pixel-identical
  to 2.6.20, because every glass surface the pref gates renders exactly what
  it did with glass off.
- The preference key move means a v2-era `true` needs one tap to re-enable.
  That is deliberate (see above) and consistent with how v1 → v2 was handled.

## Device acceptance before release

The automated matrix validates the renderer's numeric and widget contracts; visual acceptance still requires a real Android device. Before tagging 2.6.21:

1. Turn Liquid Glass **on** in Settings → Appearance. Verify the top bar, navigation dock, menus, dialogs and sheets visibly draw glass in **Light**, **Dark** and **Night**; inspect the bar while scrolling notes underneath.
2. Compare text readability and edge separation over plain pages, photos, colored notes and busy content, including with increased font size and the phone's reduced-motion setting.
3. Open and close sheets, change themes while glass is enabled, and exercise pull-to-refresh rapidly; ensure no transparent/gray first frame, dropped frame, layout overflow or crash.
4. Run a longer timeline scroll and repeated opening of menus on a slower Android device to confirm the additional active bar blur does not cause noticeable jank.
5. Upgrade an existing 2.6.20 install that had `appearance.liquid_glass_v2=true`. Confirm the new glass stays **off** until the user opts in, and that turning it on persists after restart.
6. Confirm **legacy Theme Presets remain unavailable**, and that app-lock, backup/restore, reminders and store update routing are unchanged.

Do not interpret an all-green CI as approval of visual appearance or device GPU performance; those require the phone checks above.

## Addendum — the depth pass (2.6.24)

The 2.6.21 rebuild made the material legible, transmissive and visible on every
shipped page. It still read as a *painted pane with an edge*: the films carried
no vibrancy, the optics were two strokes, and the only shadow was one 5% drop.
The fourth generation adds the missing light without changing the opt-in, the
four films, or the one-backdrop-filter-per-surface budget.

### What changed

- **Vibrancy in the same pass.** `NexVisualStyle.glassVibrancy` (1.14 light,
  1.10 dark) is applied as a saturation matrix composed *inside* the surface's
  single `BackdropFilter`, around the blur. The matrix is the Rec. 709
  luminance-preserving form (`s·C + (1−s)·Y`), so relative luminance is
  unchanged by construction and every contrast floor the films were solved
  against still holds. The old vibration attempt failed because it was a blend
  layer reading the destination; a backdrop filter always has a backdrop.
  Floating chrome gets the full matrix, panels 72% of it.
- **A light angle.** The optics painter now draws, in order: a five-stop
  hairline (key light top-left, bounce bottom-right), a 1.8px bevel ring, a
  clipped corner bloom, a soft+crisp specular pair down from the top, the
  existing bottom shade, and a centre-weighted bounce line with a short glow.
  Together they read as thickness rather than as a border.
- **Lift.** `glassAmbient` adds a tight contact shadow and a wide, very faint
  halo. Dark uses a cool halo because a black shadow on a black page is
  nothing; comfort uses a warm one. `glassEdge` is untouched at four shadows.
- **Texture.** `glassGrain` scatters deterministic 1px frost points, cached per
  surface size, only within a 16px band inside the edge. Nothing lands in the
  reading area; the floating pixel test's centre samples stay identical.
- **The bar.** It now shares the composed filter, gets a status-bar scrim, and
  draws a hairline + bounce + lit meniscus along its one exposed edge.

### Tests

- New `every glass theme carries a lit bevel, a bounce and an ambient halo`:
  the five new tokens exist and survive `copyWith`/`lerp` in Light, Dark,
  Soft Dark and OLED Night.
- Re-run and green: `packages/ui` 373; client glass-related suites (assistant,
  settings panels, dialogs, context menus, bottom bar, search field, still
  theme, appearance modes, release-two appearance) 153; whole-client suite
  separately.
- The existing numeric floors, pixel transmission ratios, BackdropFilter
  counts and high-contrast fallbacks were not relaxed.

### Limits

The vibrancy matrix runs in the compositor's colour space, not a linear one;
for mid-saturation colours the WCAG luminance can move by a small fraction of
a percent even though the sRGB luma is preserved. The floors carry enough
margin for it. Edge *displacement* refraction still needs backdrop sampling
that `ImageFilter` does not expose, so the bevel is an optical approximation,
not a bend. Device GPU cost of `ImageFilter.compose` was not measured here;
the alpha and device checklist above remain the acceptance path.
