# Nex 2.8.1 — scroll smoothness review and fixes

> Status: completed · Scope: the whole scroll path of every theme — the app
> backdrop, the timeline's per-frame work, and the difference between the
> plain Nex appearance and the textured ones (Paper above all).
> Toolchain: Flutter 3.47.9 / Dart 3.13.7 (the repo's own pin), pure-Dart
> benchmarks and the packages' full test suites.

## The report this answers

Scrolling the home screen feels markedly smoother on the plain Nex theme than
on Paper Notebook (دفتر کاغذی), and other textured themes sit somewhere
between. The brief was to find *why* a theme could change how scrolling feels,
to fix it everywhere it lives, and to leave the themes looking exactly as they
do.

## What was reviewed

Everything a scroll frame pays for, per theme:

- the app backdrop (`NexAppBackground`, `NexTextureBackdrop`,
  `NexTexturePainter`, `_BackgroundPainter`) — both the plain+texture path and
  the eight background patterns;
- the timeline's per-frame work (`_onScroll`, the sticky-day walk, the list
  differ, folding rows, the note card envelope, swipe layers, the pull strip,
  the dock, the scrim, the recap card's beam);
- rebuild discipline already shipped earlier (`_TimelineRowsCache`,
  `TimelineChange`, viewport-limited entrances, per-row repaint boundaries)
  — verified, not reworked;
- the theme switch itself (`NexThemeReveal`) and the picker's previews.

## The findings that mattered

### SCROLL-01 — a theme's motif was re-rasterized on every scroll frame

The motif each theme draws along the bottom of the screen — paper fibre on
Paper, girih stars on Isfahan turquoise, falling leaves on Autumn — is a
`CustomPainter` behind a `RepaintBoundary`, so scrolling never *re-records* it.
Recording is the cheap half. Under **Impeller**, Flutter's renderer on
Android and iOS, **there is no raster cache**: an unchanged picture's commands
are re-executed by the GPU on every frame the screen moves. A static motif
costs its whole vector drawing on each of the ~120 frames a second a phone
can spend on a flick.

Measured on the repo's own pinned toolchain, at a 390×844 logical frame
(canvas-command counts and best-of-N timings; software rasterization at 3×
device pixel ratio as the raster-cost proxy — `packages/ui/test/perf/
nex_backdrop_bench_test.dart`):

| motif | draw ops | record | raster (3×, software proxy) |
| --- | --- | --- | --- |
| none (plain Nex) | 0 | 2 µs | 20 µs |
| **fibre (Paper)** | **861** | **323 µs** | **17.9 ms** |
| girih (turquoise) | 361 | 243 µs | 16.1 ms |
| halftone (afterimage/sunflower) | 529 | 163 µs | 11.3 ms |
| stars (midnight/dusk) | 192 | 228 µs | 10.7 ms |
| threads (saffron) | 151 | 182 µs | 11.2 ms |

Every motif also carries a `saveLayer` (the fading mask that keeps the motif
from having a top edge) and a gradient `dstIn` pass — offscreen work the
plain theme simply does not have. On the GPU the absolute numbers are far
smaller than the software proxy, but the *ratio* is the finding: Paper's
backdrop was spending, per scroll frame, more raster work than the entire
visible list content — for a picture that never changes.

**Fix:** rasterize the motif once into a GPU-resident image
(`PictureRecorder` → `Picture.toImageSync` at the view's device pixel ratio)
and draw that image each frame — one textured quad, under Impeller and Skia
alike. This is exactly what Skia's raster cache used to arrange for such
pictures, done by hand where Impeller expects it. After the fix, every motif's
steady state is **1 draw command and ~8 µs of record time** (was 861 ops /
323 µs for fibre); the one-time rasterization happens when a theme is entered
or the window is resized. Images are keyed by everything the picture depends
on (motif, ink, extent, pixel size, ratio) and kept in a byte-budgeted cache
(48 MB, ≤12 entries, eviction disposes). Where an image cannot be made, the
painter falls back to the vector path it always had.

Golden files for the four palettes that render a motif were re-baselined
(±1/255 in one channel inside the band — the premultiplied-alpha rounding of
compositing an image instead of the raw ink; no visible change; the other 66
goldens are byte-identical).

### SCROLL-02 — background patterns shared a repaint boundary with the scrolling page

`NexAppBackground`'s non-plain path wrapped the pattern painter and the whole
app in **one** `RepaintBoundary`. The nearest boundary above the scrolling
viewport was that one, so every scroll frame re-recorded it — and with it the
pattern's `CustomPaint`, whose vector commands (dots: ~200 circles; weave:
~40 lines; topography: 11 paths) ran on every frame of every scroll, on the
UI thread, in addition to the raster side of SCROLL-01.

**Fix:** the pattern painter gets its own `RepaintBoundary` (recorded once,
merely referenced while the page scrolls) and the same raster-cached image as
the motifs. The outer boundary is kept, so the layer structure above the app
is unchanged.

### SCROLL-03 — the sticky-day walk climbed to the root render object

`_updateStickyDay` runs on every `ScrollUpdateNotification`, and for each
mounted `_DayMark` — the dozen-plus rows the lazy list has built — it asked
`box.localToGlobal(Offset.zero)`, a matrix walk from the row to the **root** of
the render tree, allocating along the way. Measured on a comparable tree
(30 marks, 20 levels deep): **~126 µs per frame**; the same walk relative to
the scroll viewport costs **~47 µs** — the same answers, a third of the work.

**Fix:** the walk now asks for positions relative to the scroll viewport
(`localToGlobal(point, ancestor: viewport)`) for the anchor and every mark.
Null viewport falls back to the old behaviour exactly.

### Deliberately left alone, with reasons

- The timeline list itself (SliverAnimatedList + longest-increasing-
  subsequence diffing, viewport-limited entrances, one repaint boundary per
  folding row) — already the shape the 2.6.19 review left it in; re-verified.
- The pull-to-refresh strip (`_NexPullPhysics` consuming the top overscroll,
  the drift ticker only running while a pull is under way).
- The assistant's ambient edge glow and the recap card's border beam —
  bounded laps with their own repaint boundaries, not steady scroll costs.
- `Liquid Glass` (`nexLiquidGlassAvailable = false` today): when it returns,
  a floating dock's live `BackdropFilter` will sample the scrolling page —
  the backdrop work this change removes is what it samples; nothing else
  needed doing for it now.
- The scroll haptic tick every 64 px of travel — a platform message, not a
  frame cost.
- 120 Hz: nothing in the app caps the display mode; Flutter follows the
  system's. What changes at 120 Hz is the frame budget (8.3 ms), which is
  exactly what SCROLL-01 was spending.

## Regression evidence

- `packages/ui`: full suite — 403 passing (two new benchmark harnesses in
  `test/perf/nex_backdrop_bench_test.dart`).
- `apps/client`: full suite in batches (all ~290 files) — passing, including
  the 74 goldens (8 re-baselined as above), the version/whats-new gates and
  the timeline suites.
- `packages/core` 292, `packages/data` 414, `packages/ai` 258 — all passing,
  untouched by the change but run to confirm.
- `dart analyze` clean on `packages/ui` and `apps/client`; the changed files
  are `dart format`-clean under the repo's pinned toolchain.

## Manual verification checklist (a real device)

1. **Theme parity at speed** — Nex vs Paper Notebook vs Isfahan turquoise vs
   Afterimage: fling the timeline top-to-bottom and back in each, twice.
   The difference between them should be gone; a 120 Hz panel should hold
   ~120 fps through the fling in all of them (DevTools "Performance" →
   "FPS", or `adb shell dumpsys gfxinfo <package> framestats` for the
   percentiles).
2. **Jank trace** — DevTools Performance overlay during the same fling on
   Paper: the raster (bottom) thread's spikes that used to track the motif
   should be flat now. `flutter run --profile` for honest numbers.
3. **The one-time cost** — switch into Paper and open a deep folder: the
   first frame after the switch may show the motif rasterizing once (the
   reveal animation covers it); scrolling afterwards pays nothing.
4. **Rotation and resize** — rotate the phone on Paper: the motif re-rasterizes
   once for the new size, then scrolls free.
5. **Memory** — flip through all twenty palettes in Settings → Appearance,
   then back to Paper: RSS on the raster thread should settle back (the cache
   is byte-budgeted; switching themes evicts).
6. **Pixel identity** — side by side against 2.7.2 on another device: the
   motifs are visually unchanged (goldens re-baselined by ±1/255 in-band).
7. **Background patterns** — Settings → Appearance → background: pick Dots,
   Topography and Prism, and fling the timeline in each — they now scroll
   like the plain background, where they used to be the heaviest screens in
   the app.
8. **Sticky day** — scroll slowly through a long, mixed library: the day chip
   under the filter row still names the day of the row passing beneath it,
   with no late label and no visible cost while dragging slowly.
