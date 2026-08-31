# Nex

> **Capture in Seconds. Find in Seconds.**

Nex is a local-first, minimal capture tool — the inbox for your mind. Instead of asking you
to choose a folder, a template, or hit "Save," Nex gets out of your way: tap, capture, done.
Organize later, if you ever need to.

> Nex is not a knowledge base, not a project manager, not another Notion or Obsidian. It's
> the fastest possible front door into whatever system you use to think.

Android, in English and Persian, with full right-to-left layout.

The codebase is Flutter and a Windows desktop target still builds locally, but its
CI and release jobs are paused and no Windows build is published — so Android is
what ships. iOS is not in progress.

---

## What works today

**Capture** — text, voice, photo and arbitrary files. No Save button anywhere: every
capture is committed the moment it exists. Photos go through a crop step on the way in.
Files shared to Nex from another app land the same way as ones picked inside it.

**Timeline** — one reverse-chronological stream, no folders. Cards are a fixed height, so
the list stays even. Swipe an edge for delete or add-tag; hold and drag to reorder; one
note at a time can be pinned to the top.

**Find** — SQLite FTS5 full-text search, plus tag, content-type and date filters with
tappable chips beside the search field (the `tag:`/`type:` operators still work in the
field itself). A search that matches nothing offers the nearest thing you actually wrote
rather than an empty box.

**Organize later** — tags with free-form colours, a tag manager that renames, merges and
deletes, and a trash that holds deleted notes for 30 days.

**Come back to it** — a reminder on any note, one-off or repeating, and an optional daily
nudge at an hour you pick. Both go through the OS scheduler, and when Android refuses to
schedule one — exact alarms off, notifications denied, battery optimisation — the app says
so in the OS's own words rather than failing quietly. A test-notification row in Settings
splits "Nex never sent it" from "my phone swallowed it", and deleting, restoring or editing
a note keeps its alarms exactly as honest as the notes themselves.

**Your data stays yours** — export and import a full archive, automatic throttled local
backups you can prune by hand, and a storage breakdown that tells you what is using space.

**Intelligence, optional and off by default** — transcription, OCR, summarization, tag
suggestions, semantic search and related notes, each behind its own switch, against a
provider you configure and can test, plus an assistant you can actually talk to about what
you have written. Its tone is yours to set, including one you write yourself. It is the only
part of Nex that can send a note off the device, it says so before it is switched on, and
the name you go by never leaves it. See [`docs/09-ai.md`](./docs/09-ai.md).

**Comfort** — light, dark and system themes, an optional Liquid Glass appearance with four
built-in backgrounds, an independent Comfort Mode that warms and softens any of them for
night capture, reduce-motion support, and a 48px minimum tap target enforced by tests.

**Locked if you want it** — the app can ask for the device credential or a fingerprint
whenever it comes back to the foreground. The lock is local; nothing about it is synced.

**Updates** — the app checks a public releases repo and downloads its own installer,
resuming from where it left off if the connection drops.

### Not shipped yet

Cross-device sync exists as infrastructure — a Node/PostgreSQL API, a client, and a
conflict-resolution matrix under test — but there is no pairing flow. The only way to reach
it is by pasting a base URL and a token into Settings. Treat it as unreleased.

---

## Repository layout

```
apps/
  client/     Flutter app — the product. Android ships; Windows builds, unreleased.
  backend/    Node + PostgreSQL sync API. Dormant until v2.
packages/
  core/       Domain models, ports, services. Pure Dart, no Flutter.
  data/       SQLite repository, schema, sync client. Pure Dart.
  ui/         Design tokens and shared widgets. Flutter.
  ai/         The intelligence adapters. Deletable by design — CI proves it.
spec/         Language-neutral fixtures both Dart and TypeScript read.
docs/         Product, architecture, design and decision records.
```

Two boundaries are load-bearing and are asserted in CI rather than agreed by convention:
`core` and `data` carry **zero Flutter dependency** (the `dart-packages` job never installs
Flutter — that is the assertion), and `packages/ai` can be **deleted outright** without
breaking anything else.

`packages/ui/lib/tokens/nex_tokens.dart` is the single source of truth for colour, type,
spacing, radius and motion. Nothing downstream should be spelling a hex code or a pixel gap
by hand.

---

## Getting started

Requires Flutter **3.35.5** / Dart **^3.9** (see [`.fvmrc`](./.fvmrc)). Node 20+ only if you
intend to touch the backend.

```bash
make bootstrap          # resolve every package

cd apps/client
flutter run             # Android device or emulator
flutter run -d windows  # Windows desktop — builds, but is not a released target
```

Each Dart package resolves independently and all five lockfiles are committed — a root pub
workspace is deliberately *not* used, for a reason spelled out at the top of the
[`Makefile`](./Makefile).

### Checks

`make check` reproduces the CI pipeline one-to-one. Run it before pushing.

```bash
make check          # everything
make check-dart     # core, data, ai — analyze + test, no Flutter
make check-ui       # packages/ui
make check-client   # apps/client
make check-backend  # typecheck, lint, test
make fmt            # format Dart and TypeScript
```

Analysis runs with `--fatal-infos`: an info-level lint fails the build. Format the specific
files you touched rather than sweeping the tree — a blanket `dart format` produces a large
unrelated diff.

---

## Releasing

Tag a version and [`release.yml`](./.github/workflows/release.yml) builds a signed Android
bundle and APK — the Windows installer job is paused — then publishes them to a **separate public
releases repository** — not this one.

That indirection is the point: GitHub requires authentication for a private repo's release
API and asset URLs, so an in-app updater pointed at a private source repo breaks the moment
the repo is made private, and shipping a token inside the app to fix it would mean anyone
could extract it. A public releases-only repo needs no client-side credential at all.

The one-time setup — creating that repo with a single README commit, minting a fine-grained
token scoped to it, and storing it as `RELEASES_REPO_TOKEN` — is documented at the top of
the workflow. The repo name must stay in step with `UpdateChecker`'s default in
[`app_update.dart`](./apps/client/lib/platform/app_update.dart).

GitHub attaches "Source code (zip)" and "(tar.gz)" to every release and gives no way to
suppress them. Publishing to a separate repo is what defuses that: those archives are of
the releases repo, which holds one README — not of this one.

---

## Documentation

[`docs/`](./docs) is the source of truth for how Nex is built. Code comments cite it
directly — `ADR-0nn` refers to the decision log, `FR-n.n` to the specification — so those
two are worth knowing where to find.

| Doc | Purpose |
|---|---|
| [`01-product-vision.md`](./docs/01-product-vision.md) | Why Nex exists, and the principles that are not up for negotiation |
| [`02-product-specification.md`](./docs/02-product-specification.md) | Functional requirements (`FR-n.n`) and the data model |
| [`04-architecture.md`](./docs/04-architecture.md) | Local-first architecture and the sync design |
| [`05-design.md`](./docs/05-design.md) | Design language, UI principles, accessibility floors |
| [`06-development.md`](./docs/06-development.md) | Conventions, folder structure, testing strategy |
| [`07-contributing.md`](./docs/07-contributing.md) | How to contribute |
| [`08-roadmap.md`](./docs/08-roadmap.md) | v1 → v2 → v3 sequencing |
| [`09-ai.md`](./docs/09-ai.md) | What the intelligence layer may and may not do |
| [`10-decisions.md`](./docs/10-decisions.md) | Decision log (`ADR-0nn`) — why things are the way they are |

The numbering has gaps because several documents were build-time scaffolding — a phased
build prompt, agent handoff prompts, an outstanding-work tracker, a static HTML mockup and a
duplicate of this file — and were removed once the work they described was finished. The
remaining numbers are stable because roughly ninety code comments point at them.

**Before writing code here, read [`10-decisions.md`](./docs/10-decisions.md).** Most of the
judgment calls you would otherwise have to make are already made and justified there.

---

## Contributing

Please read [`docs/07-contributing.md`](./docs/07-contributing.md) first. Nex has a narrow,
deliberate identity, and the single most common reason a contribution is declined is that it
adds friction to capture — however good the code is.

---

## License

MIT — see [`LICENSE`](./LICENSE).
