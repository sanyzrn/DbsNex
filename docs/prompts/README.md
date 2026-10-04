# Prompts

Self-contained prompts for outside agents. Each file stands alone. It
carries its own description of Nex, a map of the repository, the rules
to follow and the report format, so it can go to any model, cloud or
local, without the others.

## Pre-release review (Android)

One role per file. Reports come back in English, with findings labelled
Blocker / High / Medium / Low and each tied to a file and line.

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

Keep these files in step with the code. When a path, a feature or a rule
they name changes, update the prompt in the same pull request.
