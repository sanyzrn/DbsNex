## What does this change?

<!-- One or two sentences. Link the issue or ADR if there is one. -->

## Why?

<!-- The single most common reason a contribution is declined is that it adds
     friction to capture, however good the code is. See docs/07-contributing.md. -->

## Checklist

- [ ] `make check` passes locally (analyze + tests for every package and the backend)
- [ ] Capture still requires zero mandatory fields and no Save button
- [ ] No new dependency added to `packages/core` or `packages/ui`
- [ ] If sync semantics changed, `spec/merge-conformance.json` has a new case
- [ ] If the schema changed, a numbered migration was added under `apps/backend/src/db/migrations/`
- [ ] If a decision was made that future readers would question, `docs/10-decisions.md` has an ADR

## Risk

<!-- What breaks if this is wrong? Can it lose a user's notes? -->
