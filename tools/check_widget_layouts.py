#!/usr/bin/env python3
"""Fails if a home-screen widget layout uses a view RemoteViews cannot inflate.

The Timeline widget shipped broken and nothing here could tell. Its layout
used `<Space>` to push the capture button to the far end — a correct,
ordinary Android layout that compiles, passes lint, links, and installs.

It just never renders. RemoteViews does not inflate arbitrary views; it
inflates through a filter:

    private static final LayoutInflater.Filter INFLATER_FILTER =
            (clazz) -> clazz.isAnnotationPresent(RemoteViews.RemoteView.class);

`android.widget.Space` does not carry that annotation, and neither does a
plain `android.view.View`. The launcher throws InflateException and draws
"Problem loading widget" — on the device, in someone else's process, with
nothing in this repo's build or test output to show for it.

So the check is here instead: a widget layout may only name classes on the
platform's own allow-list. Cheap, exact, and it fails at the moment the
layout is written rather than the moment someone puts the widget on a home
screen.

The list is the set of `@RemoteView` classes in android.widget, plus the
inflater-level tags that never become a filtered class at all. It is
deliberately conservative: adding a name means checking AOSP for the
annotation first, not guessing from the fact that it looks like a widget.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Every name below was checked in AOSP (platform_frameworks_base, tag
# android-14.0.0_r1) for the annotation itself, one file at a time — the list
# is not transcribed from a blog post or from memory, because a wrong entry
# here is a widget that fails on a device with CI green behind it.
#
# ViewStub is the one that lives in android.view rather than android.widget
# and still carries it.
ALLOWED_VIEWS = {
    "AbsoluteLayout",
    "AdapterViewFlipper",
    "AnalogClock",
    "Button",
    "CheckBox",
    "Chronometer",
    "FrameLayout",
    "GridLayout",
    "GridView",
    "ImageButton",
    "ImageView",
    "LinearLayout",
    "ListView",
    "ProgressBar",
    "RadioButton",
    "RadioGroup",
    "RelativeLayout",
    "StackView",
    "Switch",
    "TextClock",
    "TextView",
    "ViewFlipper",
    "ViewStub",
}

# Handled by LayoutInflater before any class is loaded, so the filter never
# sees them.
ALLOWED_TAGS = {"include", "merge", "requestFocus", "tag"}

# Not @RemoteView, and each one is a mistake somebody will make again: the
# first three read as harmless spacers and dividers, and the last is the
# usual reflex for "just a plain box".
KNOWN_TRAPS = {
    "Space": "use layout_weight on a real view instead",
    "View": "a plain View is not @RemoteView; use a zero-content ImageView "
    "or give a neighbour layout_weight",
    "Guideline": "ConstraintLayout is not available to RemoteViews at all",
    "ConstraintLayout": "RemoteViews cannot inflate it; use LinearLayout "
    "or RelativeLayout",
}

LAYOUT_DIR = Path("apps/client/android/app/src/main/res/layout")

# Only the layouts a widget actually inflates. Everything else in this
# directory belongs to the activity, where the whole toolkit is fair game.
WIDGET_LAYOUT_GLOBS = ("widget_*.xml", "*_widget.xml")


def widget_layouts(root: Path) -> list[Path]:
    directory = root / LAYOUT_DIR
    found: set[Path] = set()
    for pattern in WIDGET_LAYOUT_GLOBS:
        found.update(directory.glob(pattern))
    return sorted(found)


def strip_comments(source: str) -> str:
    """Blanks out XML comments, keeping every newline so line numbers hold.

    Whole-file rather than line-by-line, because the comments that matter
    here span lines: widget_timeline.xml explains the <Space> bug in a
    comment that names <Space>, and a per-line stripper reported the
    explanation as the offence.
    """
    return re.sub(
        r"<!--.*?-->",
        lambda m: re.sub(r"[^\n]", " ", m.group(0)),
        source,
        flags=re.DOTALL,
    )


def offences(path: Path) -> list[tuple[int, str]]:
    found = []
    source = strip_comments(path.read_text())
    for number, line in enumerate(source.splitlines(), start=1):
        for match in re.finditer(r"<([A-Za-z][\w.]*)", line):
            tag = match.group(1)
            if tag in ALLOWED_TAGS or tag in ALLOWED_VIEWS:
                continue
            found.append((number, tag))
    return found


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    layouts = widget_layouts(root)
    if not layouts:
        print(f"::error::no widget layouts found under {LAYOUT_DIR}")
        return 1

    failed = False
    for layout in layouts:
        for number, tag in offences(layout):
            failed = True
            hint = KNOWN_TRAPS.get(tag, "not an @RemoteView class")
            rel = layout.relative_to(root)
            print(
                f"::error file={rel},line={number}::<{tag}> cannot be "
                f"inflated by RemoteViews — {hint}. The launcher would show "
                f'"Problem loading widget" instead of the widget.'
            )
    if failed:
        return 1
    print(f"{len(layouts)} widget layouts use only inflatable views")
    return 0


if __name__ == "__main__":
    sys.exit(main())
