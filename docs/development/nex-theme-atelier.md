# The Theme Atelier — whole-app palettes, rebuilt (Nex 2.6.25)

> Scope: every disabled whole-app palette, line by line — the preset layer
> (`theme_presets.dart`, `theme_preset_ramps.dart`, `minimal_theme.dart`), the appearance plumbing it
> rides (`appearance_mode.dart`, `appearance_preferences.dart`,
> `settings_palettes.dart`), the new surface-ramp token it is built on
> (`nex_surface_ramp.dart` in `packages/ui`), and every test that holds a
> palette to a floor — against `main` at `c80b467c` (PR #440, Nex 2.6.23).
> The gallery shipped paused (`nexThemePresetsAvailable = false`); this
> review rebuilt all fourteen palettes as designed objects and switched the
> gallery back on, honouring every stored choice.

## What was wrong

The palettes were not designs; they were a seed and a tint, and everything
else was derived. Five root findings, each verified in the tree before
anything was changed:

1. **A picked colour was not the colour picked.** The old
   `nexApplyThemePreset` fed every accent through
   `ColorScheme.fromSeed` with `DynamicSchemeVariant.tonalSpot`, which
   trades chroma for tonal safety. A red picked on Paper came out
   `#904A45` — brown — and read as the choice not being applied at all.
   The old code's own workaround (fidelity for four palettes, the picked
   colour kept raw) shows the derivations fighting the product.

2. **Graphite ignored the pick entirely.** Its tones were taken
   monochrome — correct for its neutrals — but the monochrome pass also
   ate the accent, so on the one palette that is grey *by design*, the one
   colour a user chose was the one colour they never saw.

3. **Derived surfaces sat beside shipped surfaces like pieces of another
   app.** The presets carried one page tint; Material derived the rest.
   The old file patched the symptoms — inputs, switches and outlined
   buttons "were still drawn in the classic palette's greys" needed a
   per-preset override — because the derived ramp never matched the Soft
   UI ramp the shipped appearances use. Glass had the same disease: each
   preset rebuilt its washes from `surfaceContainer` tones with a 72%
   film, a structure none of the shipped materials uses.

4. **One accent did two jobs.** `colorScheme.primary` was both the tone
   read as text (4.5:1) and the fill of buttons and the capture FAB, so
   every palette compromised one for the other. The shipped Soft Light
   theme already makes the split the palettes needed — `#006DCC` for text
   and fills, `#0084F7` for the capture button at the 3:1 graphical
   floor — but the preset layer had no way to express it.

5. **Still was special cases all the way down.** `nexStillColors`
   re-pinned a scheme by hand, `nexStillTheme` flattened whatever came
   out, and the preset list carried still's page tints as literal colours
   while every other preset derived from a seed. It worked, and it was
   the proof that what a palette needed was a *designed ramp*, not a
   smarter derivation.

## The rebuild

**A palette is a designed surface ramp.** `NexSurfaceRamp`
(`packages/ui/lib/tokens/nex_surface_ramp.dart`) is the seventeen colours
one Soft UI appearance is built from — page, card, elevated; ink, muted,
line, outline; the two accent steps with their inks; the selected
container and its ink; the capture button and its glyph; and the toast
action on the inverse capsule. Nothing is derived from a seed: the ramp is
the design, and `nexSoftThemeFromRamp` feeds it through the same `_theme`
constructor and the same flatten pass
(`_flattenSoftAppearance`'s exact structure) the shipped soft appearances
ride, so a palette is the same *kind* of object as Soft Light — only
recoloured end to end.

**Two accent steps, per palette.** The deep step (`accent`) draws marks,
focus rings and quiet-button labels, held to 4.5:1 against its own page,
card *and* elevated fill. The vibrant step (`fab`) is what the capture
button wears, held with its glyph to the 3:1 graphical floor — the four
palettes whose vibrant step lands between the floors (autumn 4.27,
blossom 4.41, forest 4.42, saffron 3.72) match the shipped capture
button's own 3.72 exactly rather than being darkened into the deep step.

**Glass takes the page's own colour.** `nexGlassWashFromPage` keeps the
shipped film structure — both films, the lift, both anchors, floating and
not — and swaps the anchors for the page's own hue at the lightness the
shipped anchors sit, saturation eased to their chroma. A warm page keeps
warm glass exactly the way Comfort Mode's cream anchor keeps its.

**A picked colour recolours the accent roles only.**
`NexSurfaceRamp.withAccent` keeps the palette's neutrals — they are its
identity — and walks the picked hue to the 4.5:1 text floor on the
hardest of page, card and elevated surfaces; fills take the label-safe step
(`NexAccentPalette`), the container washed from the mark itself. A red on
Graphite is red; a red on Paper is red; both keep a filled button's label
at 4.5:1.

**Still stays Still.** Its identity is the refusal to decorate: sage bone
neutrals, no motif, no glass even when the material is on elsewhere, and
the one pass that keeps inputs borderless (`nexStillTheme`, now the only
thing left in `minimal_theme.dart`).

**The atelier is a script, not a spreadsheet.** The fourteen palettes live
in `tools/theme_atelier/palettes.py` with their one-line directions, and
`palette_checker.py` mirrors the Dart colour math — WCAG luminance, HSL,
`alphaBlend`, `nexReadableOn`'s walk, the glass-wash derivation — so every
ramp is verified against every floor the tests hold *before the Dart
exists*. `emit_dart.py` writes the constants so no hex is transcribed by
hand. All fourteen pass every floor, light and dark: 4.5:1 for ink,
muted, and the deep accent as text on every ground; 3:1 boundaries with
the divider quieter than the outline; the 1.06 elevation step; every
label pair; and ink over each page's own glass on the five worst
backdrops, floating ground included.

## What the user sees

- **The gallery is back** (Settings → Appearance → Theme), and a palette
  chosen before the pause returns on its own: the same fourteen IDs, the
  same names, the same motifs, wearing the new material.
- **Tiles are windows, not labels.** Each tile builds the palette over
  the same bases the app composes (`nexSoftLightTheme`/`nexSoftDarkTheme`),
  so choosing is seeing.
- **Light, Dark, Night and System all carry the palette.** With a palette
  active, Night shows the palette's own dark design — the palette's
  identity wins over the OLED base, exactly as the previous generation
  behaved; Night's true black returns the moment the palette is switched
  back to Nex.
- **The assistant can change it again**: the palette action and the
  context line (`palette <id>`) follow `nexThemePresetsAvailable`, so
  both report the truth with the gallery live.

## Integration in Nex 2.6.25

The supplied patch was based on `c80b467c` (2.6.23). It was reviewed and
adapted onto `bdf0167d` (2.6.24), retaining the reminder fixes and the current
glass renderer, including aura, bounce, vibrancy, bevel and grain. Release
notes and version files were written separately to avoid overwriting 2.6.24.

The 28 ramp constants live in `theme_preset_ramps.dart`, keeping both Dart
files within the repository’s 800-line source limit.

Additional corrections: custom accents are opaque and clear 4.5:1 on every
ramp surface; quiet-button overrides preserve the base button geometry;
the bilingual in-app guide documents the gallery and Night behaviour; the
palette checker exits nonzero for actual failures and reports the 3:1 capture
floor separately from advisory 4.5:1 figures. New regression coverage checks
a spectrum of custom accents, current glass optics and Persian typography.

## Original agent verification (reported for the supplied patch)

The following results belong to the supplied agent report and are not a new
verification of the adapted 2.6.25 tree.

- `theme_ramp_test.dart` (new): every palette × both brightnesses holds
  the full shipped contract — structure, surfaces, ink floors, the
  pairings Material renders, the glass worst-backdrops — plus the
  identity pins (15 presets, unique IDs, seed = deep accent, Still sage
  and glass-free, Graphite grey around any pick, a picked red stays red
  on every palette with its label pairs intact).
- Every existing suite re-run green on the result: core 283, ui 373, and
  the full client suite — all 268 test files, including the appearance,
  glass, dialog, golden, portable-contract and profile coverage.
- `contracts/nex-portable-v1.json` re-pinned to the new identity colours
  (seed, light page, dark page per palette); `portable_palette_test.dart`
  follows.
- The 28 palette goldens were regenerated with the real renderer
  (`flutter test --update-goldens`); every other golden — all rendered
  with the classic theme — is byte-identical, pinning zero drift on the
  look nobody opted out of.
- Paused-era pins updated to the live-gallery contract: the settings row
  is enabled and opens the gallery (`appearance_navigation_test`), a
  stored palette is the theme in force (`app_smoke_test`), the birthday
  line follows the palette again (`release_two_appearance_test`), and an
  unknown palette name in an old backup falls back to Nex — the getter
  now sanitises, so a retired name can never reach the theme, the
  assistant context or the gallery (`restore_safety_test`).

## Risks

- **Palette changes are palette changes.** Someone who had a palette
  stored sees the redesigned one, not the 2024 original — that is the
  point of the rebuild, and the identity (name, motif, idea) is carried
  over, but the hexes are new.
- **Night + palette drops the OLED black.** Inherited behaviour, now more
  visible because the palettes are worth choosing; if OLED owners ask,
  the fix is a per-palette true-black page variant, not a revert.
- **The 72%-film preset glass is gone.** Presets now use the shipped
  film structure; with Liquid Glass on, a palette's panels transmit like
  the shipped ones do (27% light / 20% dark), which is a change from the
  old near-opaque preset wash.

## 2.6.27 — six bolder palettes, and a contrast audit

The owner asked for themes in the spirit of a set of reference shots: two
strong colours side by side rather than one accent on neutrals. Six palettes
were added on the same ramp contract, each with its own light and dark ramp
and a motif:

| id | Light | Dark | Motif |
| --- | --- | --- | --- |
| `lavender` | lilac pastels, violet accent, vivid violet capture | violet night | petals |
| `peach` | peach paper, burnt-orange marks, **charcoal capture with a peach glyph** | charcoal with peach light | fibre |
| `bloom` | cream and mustard wash, maroon ink and marks, maroon capture with a mustard glyph | mustard on deep maroon | petals |
| `dusk` | lilac mist, violet marks, peach selected wash | plum page, peach light | stars |
| `coral` | cool mist, coral-red marks, coral capture with a charcoal glyph | coral on charcoal | waves |
| `sunflower` | cream and yellow, **black capture with a yellow glyph** | yellow on black | halftone |

The ramp has one ink for every surface, so a two-tone look lives in the
capture button, the selected wash and the page, not in coloured cards with
their own ink. Filled buttons keep `fill == accent` (`theme_accent_test`).
Every new ramp passes `theme_ramp_test` unchanged, and the contract file
lists them (`contracts/nex-portable-v1.json`).

`theme_standards_test.dart` is new: every appearance × every palette × a few
picked accents at the hard ends of the wheel, on the pairs the app draws
(text 4.5:1 on each surface, boundaries and glyphs 3:1). It found and 2.6.27
fixed: `inversePrimary` was the page's accent and measured 1.4–3.5 on the
inverse capsule in every theme (now the ramp's `accentOnInverse`); the classic
light filled box (`elevated`) held the accent at 4.37 (lightened to
`#EEF0F3`); three light palettes' outlines fell to 2.93 on filled boxes
(turquoise, ocean, circuit — each a step darker); a bright picked accent
(yellow, lime) on the classic light card fell to 4.0 (now walked against the
dimmest ground).
