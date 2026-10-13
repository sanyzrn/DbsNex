# Prompts

Self-contained prompts for outside agents. Each file stands alone. It
carries its own description of Nex, a map of the repository, the rules
to follow and the report format, so it can go to any model, cloud or
local, without the others.

## Pre-release review (Android)

One role per file, for <https://github.com/sanyzrn/DbsNex>. None names a version: each reviews the latest one in the repository — the newest commit on `main` — and reads the version from `apps/client/pubspec.yaml` there, so the prompts stay usable release after release. Each prompt says how to get the code in either setup it may be given in: a model working in its own cloud workspace, which clones the repository itself, or a model on the owner's Windows PC, which clones into the folder shared with it and runs the checks package by package in PowerShell. Reports come back in
English, with findings labelled Blocker / High / Medium / Low, each tied to
a file and line, a reproduction or failing test where possible, and the test
that would catch it. Every report also carries the commit it reviewed, a
regression pass over earlier findings with the same prefix, and a coverage
ledger of every scope item — a scope item left unmentioned counts as a
failed review, not a clean one. Vault and Cycle data are treated as the most
sensitive things in the app.

The prompts are deliberately strict:

- **Start from the diff.** Every file in the reviewer's area that changed
  since the previous release is read line by line and listed.
- **"Sound" has to be earned.** A scope item marked sound names what was
  examined.
- **Try to break it.** At least one adversarial case is tried and recorded
  for every scope item.
- **Untested is a finding.** A data, privacy or money path with no test is a
  finding in itself.
- **The verdict waits for coverage.** An unchecked scope item or an unread
  changed file keeps the verdict at "Not ready until verified".

| File | Role | Finding prefix |
|---|---|---|
| [01-security-privacy.md](01-security-privacy.md) | Security and privacy | `SEC` |
| [02-data-integrity.md](02-data-integrity.md) | Data integrity and reliability | `DATA` |
| [03-ui-ux.md](03-ui-ux.md) | UI and UX | `UX` |
| [04-persian-rtl-accessibility.md](04-persian-rtl-accessibility.md) | Persian, RTL and accessibility | `LOC` |
| [05-performance-stability.md](05-performance-stability.md) | Performance and stability | `PERF` |
| [06-ai-assistant.md](06-ai-assistant.md) | AI assistant quality and safety | `AI` |
| [07-release-readiness.md](07-release-readiness.md) | Store compliance, release and code health | `REL` |

## Build tasks

| File | Task |
|---|---|
| [08-windows-panel-nex.md](08-windows-panel-nex.md) | Take Nex for Windows (`sanyzrn/Nex_windows_test`, 0.10.0) to 0.11.0: onto current upstream packages, reviewable structure, reminders/restore/links/recurring parity, desktop keyboard and two-pane UX, measured performance. Done by an agent with read-only access to both repositories: it cannot push, and returns one zip with the repository snapshot, upstream patches and hand-off notes |
| [09-windows-quality-and-design.md](09-windows-quality-and-design.md) | Take Nex for Windows from 0.11.0 to 0.12.0 as a quality round: reconcile the documents and upstream SHAs, move onto DbsNex 1.93.3, remove the CI package mirror, then a screenshot-driven visual audit and redesign of every screen (en/fa, light/dark, panel/window, text scale), at least five creative improvements, files under 500 lines, measured performance and accessibility. Same read-only, one-zip setup as 08 |
| [11-module-builder.md](11-module-builder.md) | Build one Nex module as a drop-in folder (`lib/modules/<id>/` and `test/modules/<id>/`) against the module kit (`docs/18-module-kit.md`): only the module API, words in both languages, its own storage, its own tests, the gate passing, and a README with guide and changelog lines and any platform requests. The owner adds the idea at the end; the agent hands back one zip that touches nothing else |
| [10-nex-landing-page.md](10-nex-landing-page.md) | Design and build the public Nex page at DbsStudio.ir/nex/: the site is itself a Nex timeline — a pinned download note, one day of notes (one of them a live capture card), older days answering doubts — short, minimal, Persian-first, static and self-hosted, with most of the craft left to the agent |

Keep these files in step with the code. When a path, a feature or a rule
they name changes, update the prompt in the same pull request.
