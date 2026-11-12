#!/usr/bin/env python3
"""Emit the Dart NexSurfaceRamp constants for theme_preset_ramps.dart from the
verified palettes, so no hex is transcribed by hand."""

import palettes
from palette_checker import readable_on, hexc, to_hex

# The one-line identity each pair of ramps carries in the Dart, from the
# atelier notes in palettes.py.
DIRECTIONS = {
    'still': 'warm bone and quiet sage — the flat, restful one',
    'paper': 'analog journaling — cream stock, sepia ink, brass accents',
    'autumn': 'terracotta and ember on peach cream / umber-plum dusk',
    'blossom': 'rose atelier — petal white / aubergine and orchid',
    'forest': 'pine and mist / deep woodland with mint-pine light',
    'turquoise': 'Isfahan tilework — ice white, tile teal / deep tile night',
    'saffron': 'golden saffron on warm ivory / tobacco night with marigold',
    'midnight': 'iris violet on periwinkle white / indigo with a violet glow',
    'ocean': 'marine blue on sea mist / abyssal blue with sea-glass cyan',
    'graphite': 'concrete greys and silver ink — colourless by design',
    'bauhaus': 'gallery white, ink and vermilion / charcoal, signal red',
    'porcelain': 'blue-white glaze stitched with kintsugi gold / deep glaze',
    'circuit': 'engineering cyan on a pale board / traces on midnight PCB',
    'afterimage': 'electric olive on chartreuse mist / void with electric lime',
}


def fill_derived(r):
    if r.container_ink is None:
        r.container_ink = to_hex(readable_on(hexc(r.accent), hexc(r.container)))
    if r.accent_on_inverse is None:
        r.accent_on_inverse = to_hex(
            readable_on(hexc(r.accent), hexc(r.ink)))


for t in palettes.THEMES:
    # containerInk walks this ramp's own accent onto its own container.
    for r in (t.light, t.dark):
        if r.container_ink is None:
            r.container_ink = to_hex(
                readable_on(hexc(r.accent), hexc(r.container)))
    # accentOnInverse is read on a capsule filled with this ramp's ink, and
    # both brightnesses take the LIGHT accent against it — the same formula
    # the shipped Soft Dark theme uses for its toast action.
    if t.light.accent_on_inverse is None:
        t.light.accent_on_inverse = to_hex(
            readable_on(hexc(t.light.accent), hexc(t.light.ink)))
    if t.dark.accent_on_inverse is None:
        t.dark.accent_on_inverse = to_hex(
            readable_on(hexc(t.light.accent), hexc(t.dark.ink)))


def dart_color(h):
    return f'Color(0xFF{h.lstrip("#").upper()})'


def dart_ramp(r, name):
    fields = [
        ('brightness', f'Brightness.{r.brightness}'),
        ('page', dart_color(r.page)),
        ('card', dart_color(r.card)),
        ('elevated', dart_color(r.elevated)),
        ('ink', dart_color(r.ink)),
        ('muted', dart_color(r.muted)),
        ('line', dart_color(r.line)),
        ('outline', dart_color(r.outline)),
        ('accent', dart_color(r.accent)),
        ('onAccent', dart_color(r.on_accent)),
        ('fill', dart_color(r.fill)),
        ('fillInk', dart_color(r.fill_ink)),
        ('container', dart_color(r.container)),
        ('containerInk', dart_color(r.container_ink)),
        ('fab', dart_color(r.fab)),
        ('fabInk', dart_color(r.fab_ink)),
        ('accentOnInverse', dart_color(r.accent_on_inverse)),
    ]
    body = ',\n'.join(f'  {k}: {v}' for k, v in fields)
    return f'const {name} = NexSurfaceRamp(\n{body},\n);'


# The Ramp dataclass does not carry brightness; palettes alternate light/dark.
out = []
for t in palettes.THEMES:
    l, d = t.light, t.dark
    l.brightness = 'light'
    d.brightness = 'dark'
    out.append(f'// {t.id}: {DIRECTIONS[t.id]}')
    out.append(dart_ramp(l, f'_{t.id}Light'))
    out.append(dart_ramp(d, f'_{t.id}Dark'))
print('\n\n'.join(out))
