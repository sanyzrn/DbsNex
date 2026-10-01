#!/usr/bin/env python3
"""Builds Nex's own icon and brand pictures from the artwork in docs/.

Sources (kept in docs/ as delivered by the designer):

- nex_logo.svg — the octopus mark; its ink parts are #1d1d1d, the blue #08f;
- nex_logo_type.svg — the "nex" logotype; ink #231f20, blue #0084f7;
- alt4.png — the app icon since 1.90: the logotype on #1D1D1D, 1024×1024;
- alt1.png, alt2.png, alt3.png, alt5.png — the icons offered in Settings
  (alt1, the octopus, was the app icon in 1.83–1.89);
- dark_splash.png, light_splash.png, text_logo_dark.png, text_logo_light.png.

Run from the repo root, then tools/generate_app_icons.py for the switcher:

    python3 tools/generate_brand_assets.py
    python3 tools/generate_app_icons.py

This writes the Android launcher icon (adaptive foreground and monochrome
layers drawn from the SVG, so they stay sharp, plus the Android 7 bitmap),
the Android 12 splash icon, the iOS and Windows icons, the in-app branding
pictures and the sources for the icon switcher: app_icons/alt1-4 are
docs/alt2, alt3, alt1 (the octopus, in the slot the logotype held) and alt5;
app_icons/alt5 is the older mark, kept as the "classic" icon and not touched
here. The Android 12 splash icon stays the octopus's eyes: the opening
animation (NexSplash) starts from them.

Requires Pillow and CairoSVG (pip install pillow cairosvg).
"""

from pathlib import Path
import io
import re
import shutil

import cairosvg
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
CLIENT = ROOT / "apps" / "client"
RES = CLIENT / "android" / "app" / "src" / "main" / "res"
BRANDING = CLIENT / "assets" / "branding"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

LOGO = (DOCS / "nex_logo.svg").read_text()
VIEW = (236.1915, 274.4374)
# Where the mark's ink sits inside its viewBox, and where alt1 puts it on its
# 1024 square; the foreground layer is drawn to land on exactly those pixels.
MARK_BOX = (21.8, 22.7, 214.3, 251.6)
ICON_BOX = (267, 221, 758, 803)

PAPER = "#F4F5F5"
ICON_BLUE = "#417CBE"
INK = "#1D1D1D"

LOGOTYPE = (DOCS / "nex_logo_type.svg").read_text()
TYPE_VIEW = (900.0822, 217.1348)
# Where the logotype's ink sits inside its viewBox, and where alt4 puts it.
TYPE_BOX = (34.5, 13.75, 890.5, 198.75)
TYPE_ICON_BOX = (221, 450, 802, 575)
TYPE_BLUE = "#0084F7"


def mark(canvas, box, ink, blue, eyes_only=False):
    """The mark on a transparent canvas, its ink fitted to box=(x0, y0, x1, y1)."""
    svg = LOGO.replace('fill="#1d1d1d"', f'fill="{ink}"').replace(
        'fill="#08f"', f'fill="{blue}"'
    )
    if eyes_only:
        svg = re.sub(r"<path [^>]*/>", "", svg)
    s = (box[2] - box[0]) / (MARK_BOX[2] - MARK_BOX[0])
    w, h = VIEW[0] * s, VIEW[1] * s
    png = cairosvg.svg2png(
        bytestring=svg.encode(),
        output_width=round(w * 4),
        output_height=round(h * 4),
    )
    art = Image.open(io.BytesIO(png)).convert("RGBA")
    art = art.resize((round(w), round(h)), Image.LANCZOS)
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    out.alpha_composite(
        art, (round(box[0] - MARK_BOX[0] * s), round(box[1] - MARK_BOX[1] * s))
    )
    return out


def logotype(canvas, box, ink, blue):
    """The logotype on a transparent canvas, its ink fitted to box."""
    svg = LOGOTYPE.replace('fill="#231f20"', f'fill="{ink}"').replace(
        'fill="#0084f7"', f'fill="{blue}"'
    )
    s = (box[2] - box[0]) / (TYPE_BOX[2] - TYPE_BOX[0])
    w, h = TYPE_VIEW[0] * s, TYPE_VIEW[1] * s
    png = cairosvg.svg2png(
        bytestring=svg.encode(),
        output_width=round(w * 4),
        output_height=round(h * 4),
    )
    art = Image.open(io.BytesIO(png)).convert("RGBA")
    art = art.resize((round(w), round(h)), Image.LANCZOS)
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    out.alpha_composite(
        art, (round(box[0] - TYPE_BOX[0] * s), round(box[1] - TYPE_BOX[1] * s))
    )
    return out


def visible(art):
    """The part a launcher shows of a 108 dp layer: the central 72 dp."""
    inset = round(art.width * 18 / 108)
    return art.crop((inset, inset, art.width - inset, art.height - inset))


def rounded(image, radius):
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, image.width - 1, image.height - 1),
        radius=round(image.width * radius),
        fill=255,
    )
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def android_launcher(icon):
    foreground = logotype((1024, 1024), TYPE_ICON_BOX, PAPER, TYPE_BLUE)
    monochrome = logotype((1024, 1024), TYPE_ICON_BOX, "#FFFFFF", "#FFFFFF")
    for density, scale in DENSITIES.items():
        folder = RES / f"mipmap-{density}"
        layer = round(108 * scale)
        foreground.resize((layer, layer), Image.LANCZOS).save(
            folder / "ic_launcher_foreground.png", optimize=True
        )
        monochrome.resize((layer, layer), Image.LANCZOS).save(
            folder / "ic_launcher_monochrome.png", optimize=True
        )
        legacy = round(48 * scale)
        rounded(visible(icon).resize((legacy, legacy), Image.LANCZOS), 0.22).save(
            folder / "ic_launcher.png", optimize=True
        )


def android_splash():
    """Android 12's splash icon: only the eyes, where the Flutter splash starts.

    Without an icon background the system draws the icon at 288 dp; the
    Flutter splash (NexSplash) opens on the same two eyes at the same place
    and size, then draws the rest of the octopus around them.
    """
    side = 480
    # The mark is 96 dp wide on screen (NexSplash.markWidth) and the icon
    # 288 dp across, so it spans a third of the picture, centred.
    width = side / 3
    height = width * (MARK_BOX[3] - MARK_BOX[1]) / (MARK_BOX[2] - MARK_BOX[0])
    box = (
        (side - width) / 2,
        (side - height) / 2,
        (side + width) / 2,
        (side + height) / 2,
    )
    folder = RES / "drawable"
    mark((side, side), box, INK, "#0084F7", eyes_only=True).save(
        folder / "nex_splash_icon_light.png", optimize=True
    )
    mark((side, side), box, PAPER, "#0084F7", eyes_only=True).save(
        folder / "nex_splash_icon_dark.png", optimize=True
    )


def ios(icon):
    folder = CLIENT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for path in folder.glob("Icon-App-*.png"):
        size, scale = re.match(r"Icon-App-([\d.]+)x[\d.]+@(\d)x", path.name).groups()
        px = round(float(size) * int(scale))
        icon.convert("RGB").resize((px, px), Image.LANCZOS).save(path, optimize=True)


def windows(icon):
    path = CLIENT / "windows" / "runner" / "resources" / "app_icon.ico"
    rounded(icon, 0.22).save(
        path, sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    )


def branding():
    for name in (
        "dark_splash.png",
        "light_splash.png",
        "text_logo_dark.png",
        "text_logo_light.png",
    ):
        shutil.copyfile(DOCS / name, BRANDING / name)


def switcher_sources():
    for slot, source in ((1, 2), (2, 3), (3, 1), (4, 5)):
        shutil.copyfile(
            DOCS / f"alt{source}.png", CLIENT / "app_icons" / f"alt{slot}.png"
        )


def main():
    icon = Image.open(DOCS / "alt4.png").convert("RGBA")
    switcher_sources()
    android_launcher(icon)
    android_splash()
    ios(icon)
    windows(icon)
    branding()
    print("done; now run tools/generate_app_icons.py")


if __name__ == "__main__":
    main()
