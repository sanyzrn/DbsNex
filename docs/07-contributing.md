# Contributing to Nex

> Thanks for helping make capture effortless. Nex is built in the open, and good contributions are welcome — especially ones that make capture **faster** or the surface **simpler**.

**Status:** Authoritative · **Owner:** Maintainers · **Last updated:** 2026

---

## Before You Contribute

Nex has a narrow, deliberate identity. Please read these first:

- [`01-product-vision.md`](./01-product-vision.md) — especially [Non-Negotiable Principles](./01-product-vision.md#non-negotiable-principles)
- [`02-product-specification.md`](./02-product-specification.md) — current scope and explicit non-goals
- [`10-decisions.md`](./10-decisions.md) — why things are the way they are, so you don't relitigate settled questions

**The single most common reason a pull request is rejected is that it adds friction to capture, even if the code is technically excellent.** If you're unsure whether a feature belongs, open a discussion issue before writing code.

---

## Ways to Contribute

- 🐛 **Bug fixes** — especially anything affecting capture reliability, offline behavior, or search correctness.
- ⚡ **Performance improvements** — especially to capture-to-save and query-to-result latency.
- 🎨 **Accessibility / design polish** — see [`05-design.md`](./05-design.md#accessibility).
- 📚 **Documentation** — clarifications, corrections, translations.
- 🗺️ **Roadmap features** — see [`08-roadmap.md`](./08-roadmap.md); features already scoped for an upcoming version are the best place to start.
- 💡 **New feature proposals** — must go through a Discussion/Issue first (see below), since anything not already on the roadmap needs an identity check against the non-negotiable principles.

**Not sought right now:** scope-expanding features (transcription, sync internals beyond what's specified, generic files ahead of v2, semantic search) are version-gated and tracked by maintainers.

## What We Will Not Merge

- Anything that adds a required field, dialog, or decision point to the capture flow (title, folder, template, confirmation prompts).
- Anything that turns Nex into a general-purpose knowledge base, project manager, or collaboration tool.
- Features that make AI a blocking step in capture.
- Dependencies that meaningfully increase app size or cold-start time without a corresponding, justified capability the product needs today.
- Speculative abstractions/config systems for functionality not on the current roadmap.

> If your PR adds a Save button, a required title, a folder hierarchy, or a network call to capture — it will be declined. These are product principles, not preferences.

---

## Development Setup

See [`06-development.md`](./06-development.md) for folder structure, conventions, and testing strategy.

```bash
git clone https://github.com/<org>/nex.git
cd nex
npm install
npm run test --workspace=packages/core
```

---

## Proposing a Change

1. **Search existing issues** to avoid duplicates.
2. **For anything beyond a small fix, open an issue first** describing the problem, the proposed solution, and — critically — how it aligns with Nex's identity and non-negotiable principles.
3. **Wait for maintainer feedback** on scope before investing significant implementation time.

### Feature Proposal Template

- The problem being solved, from a real user scenario.
- Why existing capture/search/tag primitives don't already solve it.
- An explicit statement of how the feature preserves Capture First, Organize Later, and Find Instantly.
- Any UX decisions it would introduce at capture time (if none, say so explicitly — this is often the deciding factor).

Accepted proposals are added to [`08-roadmap.md`](./08-roadmap.md) with a target version before implementation begins.

---

## Pull Request Process

1. Fork the repository and create a branch following [`06-development.md`](./06-development.md#naming-conventions): `type/short-description`.
2. Write tests for any new logic, prioritizing Core domain and Data layer coverage.
3. Ensure the full CI suite passes locally before opening the PR: lint, type-check, unit/integration tests, and performance budget checks.
4. Fill out the PR template, explicitly answering:
   - What problem does this solve?
   - Does this change the capture flow? If yes, what is the measured impact on capture time?
   - Does this align with a specific principle in the Vision or Specification docs?
5. Keep PRs focused and small; large multi-concern PRs will be asked to split.
6. At least one maintainer approval and a green CI run are required before merge.
7. Maintainers squash-merge using a Conventional Commits-formatted message.

## Pull Request Checklist

- [ ] No added capture friction — the capture path stays under budget, offline.
- [ ] Local-first preserved — no new hard dependency on the network.
- [ ] Tests added/updated for the behavior changed.
- [ ] Performance budgets met (see [`02-product-specification.md`](./02-product-specification.md#non-functional-requirements)).
- [ ] Accessibility maintained (keyboard, contrast, reduced-motion).
- [ ] Docs updated if behavior or architecture changed.
- [ ] Fits scope — does not expand v1 scope into v2/v3 territory.

---

## Code Review Standards

Reviewers evaluate PRs in this order:

1. Does it preserve the capture and find performance guarantees?
2. Does it preserve offline-first behavior?
3. Does it avoid adding any decision point to the capture flow?
4. Is it well-tested per the [Testing Strategy](./06-development.md#testing-strategy)?
5. Is it consistent with existing conventions and design language ([`05-design.md`](./05-design.md))?

---

## Reporting Bugs

Please include:
- Platform and version (Android/Windows/iOS, app version, online/offline).
- Steps to reproduce.
- Expected vs. actual behavior.
- Whether the issue affects capture, search, sync, or another area.
- Logs, if available — **never** include actual note content in a public bug report (see [Logging](./06-development.md#logging)).

**Security or data-loss bugs:** do not open a public issue. Email the maintainers privately.

---

## Community Standards

Be respectful and constructive in issues, discussions, and reviews. Assume good faith; the project's narrow scope means many well-intentioned ideas will still be declined — that's a reflection of focus, not of the idea's merit elsewhere. All contributors are expected to follow the Contributor Covenant v2.1, enforced by maintainers.

---

## License

By contributing, you agree that your contributions will be licensed under the project's [MIT License](../LICENSE).
