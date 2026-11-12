#!/usr/bin/env python3
"""Nex Theme Atelier — palette floor verifier.

Mirrors the Dart colour math (WCAG luminance, HSL, alphaBlend, readableOn
walk, glass-wash derivation) so every ramp pinned in theme_preset_ramps.dart can
be verified against every floor the app's tests hold, before the Dart exists.
"""
from dataclasses import dataclass


# ---------------------------------------------------------------- colour math
def srgb_to_linear(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def luminance(c):
    r, g, b = c
    return (0.2126 * srgb_to_linear(r) + 0.7152 * srgb_to_linear(g)
            + 0.0722 * srgb_to_linear(b))


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def hexc(s):
    s = s.lstrip('#')
    return (int(s[0:2], 16) / 255, int(s[2:4], 16) / 255, int(s[4:6], 16) / 255)


def to_hex(c):
    return '#%02X%02X%02X' % tuple(max(0, min(255, round(x * 255))) for x in c)


def hsl_from_color(c):
    """Flutter HSLColor.fromColor (H in degrees, S/L 0..1)."""
    r, g, b = c
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2
    if mx == mn:
        h = s = 0.0
    else:
        d = mx - mn
        s = d / (2 - mx - mn) if l > 0.5 else d / (mx + mn)
        if mx == r:
            h = (g - b) / d + (6 if g < b else 0)
        elif mx == g:
            h = (b - r) / d + 2
        else:
            h = (r - g) / d + 4
        h *= 60
    return h, s, l


def hsl_to_color(h, s, l):
    """Flutter HSLColor.toColor."""
    c = (1 - abs(2 * l - 1)) * s
    m = l - c / 2
    hp = (h % 360) / 60
    x = c * (1 - abs(hp % 2 - 1))
    if 0 <= hp < 1:
        r, g, b = c, x, 0
    elif hp < 2:
        r, g, b = x, c, 0
    elif hp < 3:
        r, g, b = 0, c, x
    elif hp < 4:
        r, g, b = 0, x, c
    elif hp < 5:
        r, g, b = x, 0, c
    else:
        r, g, b = c, 0, x
    return (r + m, g + m, b + m)


def alpha_blend(src, dst, alpha):
    """Flutter Color.alphaBlend for a straight-alpha src over opaque dst."""
    if alpha == 0:
        return dst
    inv = 1 - alpha
    return tuple(src[i] * alpha + dst[i] * inv for i in range(3))


def readable_on(color, ground, ratio=4.5):
    """nexReadableOn: darken on light ground, lighten on dark, hue kept."""
    if contrast(color, ground) >= ratio:
        return color
    darken = luminance(ground) > 0.18
    h, s, l = hsl_from_color(color)
    for _ in range(100):
        l = max(0.0, min(1.0, l + (-0.01 if darken else 0.01)))
        cand = hsl_to_color(h, s, l)
        if contrast(cand, ground) >= ratio or l in (0, 1):
            return cand
    return hsl_to_color(h, s, l)


# ------------------------------------------------------------- glass washes
def anchor_tone(page, lightness, max_saturation=0.18):
    h, s, l = hsl_from_color(page)
    s = min(s * 0.7, max_saturation)
    return hsl_to_color(h, s, lightness)


def glass_wash_from_page(page, brightness, floating=False):
    dark = brightness == 'dark'
    page = hexc(page)
    if not dark:
        tone = anchor_tone(page, 0.86)
        if floating:
            films = [(hexc('#000000'), 0.02), (hexc('#FFFFFF'), 0.42)]
            lift = ((1, 1, 1), 0.06)
            anchor = (tone, 0.30)
        else:
            films = [(hexc('#000000'), 0.06), (hexc('#FFFFFF'), 0.32)]
            lift = ((1, 1, 1), 0.08)
            anchor = (tone, 0.54)
    else:
        tone_l = anchor_tone(page, 0.16)
        tone_a = anchor_tone(page, 0.21)
        if floating:
            films = [(hexc('#FFFFFF'), 0.02), (hexc('#000000'), 0.66)]
            lift = (tone_l, 0.10)
            anchor = (tone_a, 0.02)
        else:
            films = [(hexc('#FFFFFF'), 0.05), (hexc('#000000'), 0.48)]
            lift = (tone_l, 0.42)
            anchor = (tone_a, 0.30)
    return {'films': films, 'lift': lift, 'anchor': anchor}


def wash_over_full(wash, backdrop):
    result = backdrop
    for film, a in wash['films']:
        result = alpha_blend(film, result, a)
    result = alpha_blend(wash['lift'][0], result, wash['lift'][1])
    result = alpha_blend(wash['anchor'][0], result, wash['anchor'][1])
    return result


def floating_contrast_ground(page, brightness):
    dark = brightness == 'dark'
    wash = glass_wash_from_page(page, brightness, floating=True)
    base = wash_over_full(wash, (1, 1, 1) if dark else (0, 0, 0))
    if dark:
        src, a = (1, 1, 1), 0.12 * 0.6   # glassHighlight white 12% * 0.6
    else:
        src, a = (0, 0, 0), 0.04 * 0.6   # glassDepth black 4% * 0.6
    return alpha_blend(src, base, a)


# ------------------------------------------------------------------- ramps
@dataclass
class Ramp:
    page: str
    card: str
    elevated: str
    ink: str
    muted: str
    line: str
    outline: str
    accent: str
    on_accent: str          # pairs with `accent` (scheme.onPrimary)
    fill: str
    fill_ink: str           # pairs with `fill` (filled buttons)
    container: str
    container_ink: str = None   # filled by verifier when None
    fab: str = None
    fab_ink: str = None
    accent_on_inverse: str = None  # filled by verifier

    def __post_init__(self):
        if self.fab is None:
            self.fab = self.accent
        if self.fab_ink is None:
            self.fab_ink = self.on_accent


def check_all(r, label, failures):
    def fail(msg):
        failures.append(f'{label}: {msg}')

    page, card, elev = hexc(r.page), hexc(r.card), hexc(r.elevated)
    ink, muted = hexc(r.ink), hexc(r.muted)
    line, outline = hexc(r.line), hexc(r.outline)
    accent, fill = hexc(r.accent), hexc(r.fill)
    fill_ink, container = hexc(r.fill_ink), hexc(r.container)
    fab, fab_ink = hexc(r.fab), hexc(r.fab_ink)

    if r.page == r.card:
        fail('card equals page')
    if contrast(outline, card) < 3.0:
        fail(f'outline vs card {contrast(outline, card):.2f} < 3.0')
    if not contrast(line, card) < contrast(outline, card):
        fail(f'line not quieter than outline ({contrast(line, card):.2f} >= {contrast(outline, card):.2f})')
    if contrast(elev, card) < 1.06:
        fail(f'elevated vs card {contrast(elev, card):.2f} < 1.06 (invisible step)')
    if contrast(outline, elev) < 1.6:
        fail(f'outline vs elevated {contrast(outline, elev):.2f} < 1.6')
    for ground, gname in [(page, 'page'), (card, 'card'), (elev, 'elevated')]:
        if contrast(ink, ground) < 4.5:
            fail(f'ink vs {gname} {contrast(ink, ground):.2f} < 4.5')
        if contrast(muted, ground) < 4.5:
            fail(f'muted vs {gname} {contrast(muted, ground):.2f} < 4.5')
    for ground, gname in [(page, 'page'), (card, 'card'), (elev, 'elevated')]:
        if contrast(accent, ground) < 4.5:
            fail(f'accent(text) vs {gname} {contrast(accent, ground):.2f} < 4.5')
    if contrast(fill_ink, fill) < 4.5:
        fail(f'fillInk vs fill {contrast(fill_ink, fill):.2f} < 4.5')
    on_accent = hexc(r.on_accent)
    if contrast(on_accent, accent) < 3.0:
        fail(f'onPrimary vs primary(icon) {contrast(on_accent, accent):.2f} < 3.0')
    if contrast(on_accent, accent) < 4.5:
        fail(f'note: onAccent vs accent only {contrast(on_accent, accent):.2f} (aim 4.5)')
    if r.container_ink is None:
        r.container_ink = to_hex(readable_on(accent, container))
    cink = hexc(r.container_ink)
    if contrast(cink, container) < 4.5:
        fail(f'containerInk vs container {contrast(cink, container):.2f} < 4.5')
    if contrast(fab_ink, fab) < 3.0:
        fail(f'fabInk vs fab {contrast(fab_ink, fab):.2f} < 3.0')
    # glass floors: ink over the wash on the 5 worst backdrops
    brightness = 'dark' if luminance(page) < 0.18 else 'light'
    wash = glass_wash_from_page(r.page, brightness)
    for bg in ['#FFFFFF', '#000000', '#FF0000', '#0000FF', '#00FF00']:
        surface = wash_over_full(wash, hexc(bg))
        if contrast(ink, surface) < 4.5:
            fail(f'glass ink over {bg}: {contrast(ink, surface):.2f} < 4.5')
    ground = floating_contrast_ground(r.page, brightness)
    if contrast(ink, ground) < 4.5:
        fail(f'floating ink worst ground: {contrast(ink, ground):.2f} < 4.5')


def main():
    import palettes
    failures = []
    for theme in palettes.THEMES:
        for which in ('light', 'dark'):
            check_all(getattr(theme, which), f'{theme.id}.{which}', failures)
    for theme in palettes.THEMES:
        light, dark = theme.light, theme.dark
        if light.accent_on_inverse is None:
            light.accent_on_inverse = to_hex(
                readable_on(hexc(light.accent), hexc(light.ink)))
        if dark.accent_on_inverse is None:
            dark.accent_on_inverse = to_hex(
                readable_on(hexc(light.accent), hexc(dark.ink)))
        for which, r in (('light', light), ('dark', dark)):
            if contrast(hexc(r.accent_on_inverse), hexc(r.ink)) < 4.5:
                failures.append(
                    f'{theme.id}.{which}: accentOnInverse on ink '
                    f'{contrast(hexc(r.accent_on_inverse), hexc(r.ink)):.2f} < 4.5')
    if failures:
        print(f'--- {len(failures)} failures ---')
        for f in failures:
            print(' FAIL', f)
    else:
        print('All floors cleared.')
    for theme in palettes.THEMES:
        for which in ('light', 'dark'):
            r = getattr(theme, which)
            ratio = contrast(hexc(r.fab_ink), hexc(r.fab))
            if 3 <= ratio < 4.5:
                print(f' NOTE {theme.id}.{which}: capture glyph {ratio:.2f}:1 (floor 3:1)')
    print()
    for theme in palettes.THEMES:
        for which in ('light', 'dark'):
            r = getattr(theme, which)
            print(f"{theme.id}.{which}: containerInk={r.container_ink} "
                  f"accentOnInverse={r.accent_on_inverse}")

    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
