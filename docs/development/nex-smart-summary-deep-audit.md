# Smart Summary deep audit — Nex 2.6.19

## Applied fixes

- **Critical notes beyond the timeline window:** Briefs now fetch due and urgent notes outside the recency-limited timeline, using a dedicated DB-worker query and stable per-ID merge.
- **Urgent-note priority:** The reviewed query now sorts urgent notes ahead of dated notes before its 200-note cap. A new regression test exercises >200 reminders plus an urgent note.
- **Manual refresh:** A pull that joins an already-running automatic flight is honored; a forced settings update is not mistaken for a manual gesture.
- **Local report consistency:** The report style no longer repeatedly compares its freshly computed text with an unrelated model cache.
- **Bounded headline context:** The greeting sends capped note excerpts rather than full note bodies.
- **Locale invalidation and compute reduction:** Resolved interface language enters the settings signature, and recap-line generation stops at its budget.

The original review described 16 changed files and 13 new targeted tests; this integration also adds a database-priority regression test and updates the corresponding expected ordering.

## Integration guardrails

- Applied to the Nex 2.6.19 `main` baseline (after performance release PR #433) without changing the app version or data schema.
- The dedicated integration workflow checks the full uploaded patch's SHA-256 and applies it with `git apply --check` before committing the actual sources.
- Normal core/data/client CI and Android build must pass before merging this PR.
- On-device manual checks should cover: old urgent and reminder notes beyond 200 entries; automatic and pull-to-refresh overlap; Report style with AI disabled; Persian/English/system-locale switching; and the greeting with a very long note.

## Known bounded behavior

The supplemental waiting-note query intentionally caps output at 200 entries per pass. Under exceptionally large waiting sets, lower-priority items may still be outside that cap. An empty result on DB-read failure falls back to the timeline window rather than crashing Smart Summary.
