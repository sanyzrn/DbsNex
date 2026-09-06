#!/usr/bin/env python3
"""Checks the checker.

The guard's whole value is that it fails on the exact layout that shipped
broken, so that is what it is tested against — plus the cases where a
checker like this usually goes wrong: passing because it found nothing to
look at, and failing on a comment that merely names the offending tag.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "check_widget_layouts.py"
LAYOUTS = Path("apps/client/android/app/src/main/res/layout")


def run(root: Path) -> subprocess.CompletedProcess[str]:
    tool = root / "tools" / "check_widget_layouts.py"
    return subprocess.run(
        [sys.executable, str(tool)], capture_output=True, text=True
    )


def scaffold(directory: Path, layouts: dict[str, str]) -> Path:
    root = directory / "repo"
    (root / "tools").mkdir(parents=True)
    (root / "tools" / "check_widget_layouts.py").write_text(TOOL.read_text())
    target = root / LAYOUTS
    target.mkdir(parents=True)
    for name, body in layouts.items():
        (target / name).write_text(body)
    return root


HEADER = '<?xml version="1.0" encoding="utf-8"?>\n'


def case(name, layouts, expect_exit, expect_in_output=None):
    with tempfile.TemporaryDirectory() as tmp:
        root = scaffold(Path(tmp), layouts)
        result = run(root)
        output = result.stdout + result.stderr
        if result.returncode != expect_exit:
            print(f"FAIL {name}: exit {result.returncode}, want {expect_exit}")
            print(output)
            return False
        if expect_in_output and expect_in_output not in output:
            print(f"FAIL {name}: output missing {expect_in_output!r}")
            print(output)
            return False
        print(f"ok   {name}")
        return True


def main() -> int:
    good = HEADER + (
        '<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <TextView android:layout_weight="1" />\n'
        "  <ImageView />\n"
        "</LinearLayout>\n"
    )
    # The layout as it actually shipped: a Space doing the pushing.
    shipped = HEADER + (
        '<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android">\n'
        "  <TextView />\n"
        '  <Space android:layout_weight="1" />\n'
        "  <ImageView />\n"
        "</LinearLayout>\n"
    )
    commented = HEADER + (
        '<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android">\n'
        "  <!-- There used to be a <Space> here; see the RemoteViews filter.\n"
        "       A <View> would be just as wrong. -->\n"
        '  <TextView android:layout_weight="1" />\n'
        "</LinearLayout>\n"
    )

    results = [
        case("a clean widget layout passes", {"widget_timeline.xml": good}, 0),
        case(
            "the layout that shipped broken fails",
            {"widget_timeline.xml": shipped},
            1,
            "<Space> cannot be inflated",
        ),
        case(
            "a plain View fails too",
            {
                "widget_timeline.xml": HEADER
                + "<FrameLayout><View /></FrameLayout>\n"
            },
            1,
            "<View> cannot be inflated",
        ),
        case(
            "a multi-line comment naming the tag is not a use",
            {"widget_timeline.xml": commented},
            0,
        ),
        case(
            "both naming conventions are covered",
            {"capture_widget.xml": shipped},
            1,
            "<Space> cannot be inflated",
        ),
        # The failure mode a checker like this dies of: it keeps passing
        # after the files it guards move or get renamed.
        case("no layouts at all is a failure, not a pass", {}, 1, "no widget layouts"),
    ]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
