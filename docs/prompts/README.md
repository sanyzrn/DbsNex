# Prompts

Self-contained prompts for outside agents. Each file stands alone. It
carries its own description of Nex, a map of the repository, the rules
to follow and the report format, so it can go to any model, cloud or
local, without the others.

## Pre-release review (Android)

One role per file. Reports come back in Persian, with findings labelled
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
| [08-windows-panel-nex.md](08-windows-panel-nex.md) | Bring Nex into the Flutter port of Right Panel, as `apps/desktop` |

Keep these files in step with the code. When a path, a feature or a rule
they name changes, update the prompt in the same pull request.
