#!/usr/bin/env python3
"""Require the checks selected by the path filter, allowing intentional skips."""

import json
import os
import sys


def failures(needs: dict) -> list[str]:
    outputs = needs.get("changes", {}).get("outputs", {})
    if any(outputs.get(key) not in ("true", "false") for key in ("dart", "backend")):
        return ["changes must supply valid dart/backend flags"]
    dart = outputs["dart"] == "true"
    backend = outputs["backend"] == "true"
    required = {
        "changes": True, "core-boundary": True, "widget-layouts": True,
        "dart-packages": dart, "retrieval-budget": dart, "timeline-budget": dart,
        "flutter-ai-package": dart, "flutter-ui-package": dart,
        "client-android": dart, "ai-deletion-proof": dart,
        "backend": backend, "feedback-worker": backend,
        "merge-conformance": dart or backend, "sync-integration": dart or backend,
        # Explicitly paused in ci.yml. Failures/cancellations still fail.
        "client-windows": False, "client-ios": False,
    }
    errors = [f"missing required dependency: {name}" for name in required if name not in needs]
    for name, job in needs.items():
        result = job.get("result")
        allowed = ("success",) if required.get(name, True) else ("success", "skipped")
        if result not in allowed:
            errors.append(f"{name}: {result!r}; expected {' or '.join(allowed)}")
    return errors


def main() -> int:
    try:
        errors = failures(json.loads(os.environ["CI_NEEDS"]))
    except (KeyError, ValueError, TypeError, AttributeError) as error:
        errors = [f"invalid CI dependency summary: {error}"]
    for error in errors:
        print(f"::error::{error}")
    if not errors:
        print("All selected checks succeeded; only intentional skips were accepted.")
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
