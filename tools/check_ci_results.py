#!/usr/bin/env python3
"""Require the checks selected by the path filter, allowing intentional skips."""

import json
import os
import sys

SELECTION = ('dart', 'client', 'content', 'guards', 'format', 'android',
             'backend', 'desktop', 'retrieval', 'sync', 'ai_delete')

# Jobs that exist in ci.yml but are deliberately paused: their `if:` is false,
# so a skipped result is the only thing they can report. Anything not listed
# here and not in `required` is a job this gate does not know about, which
# `check_ci_results_test.WorkflowDriftTest` refuses.
PAUSED = ('client-windows', 'client-ios')


def required_jobs(selected: dict) -> dict:
    """Which jobs a run must report as run, keyed the way `needs` is."""
    return {
        "changes": True,
        "guard": selected["guards"],
        "changed-format": selected["format"],
        "dart-packages": selected["dart"],
        "retrieval-budget": selected["retrieval"],
        "timeline-budget": selected["client"],
        "flutter-ai-package": selected["dart"],
        "flutter-ui-package": selected["dart"],
        "client-tests": selected["client"] or selected["content"],
        "client-android-build": selected["android"],
        "backend": selected["backend"],
        "feedback-worker": selected["backend"],
        "sync-integration": selected["sync"],
        "ai-deletion-proof": selected["ai_delete"],
        # Paused in ci.yml: only a skip can be reported, but a failure or a
        # cancellation still fails. `WorkflowDriftTest` holds this list to the
        # workflow, so unpausing a job cannot leave it quietly optional.
        **dict.fromkeys(PAUSED, False),
    }


def failures(needs: dict) -> list[str]:
    outputs = needs.get("changes", {}).get("outputs", {})
    errors = [f"changes must supply a valid {key} flag"
              for key in SELECTION if outputs.get(key) not in ("true", "false")]
    selected = {key: outputs.get(key) == "true" for key in SELECTION}
    required = required_jobs(selected)
    errors += [f"missing required dependency: {name}" for name in required if name not in needs]
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
