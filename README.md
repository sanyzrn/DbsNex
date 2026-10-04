<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/brand/readme_logo_dark.png">
  <img src="docs/brand/readme_logo_light.png" alt="Nex — AI Second Memory" width="360">
</picture>

### Capture in seconds. Find in seconds.

A local-first capture app for Android, in Persian and English, with full right-to-left layout.

[![CI](https://github.com/sanyzrn/DbsNex/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/sanyzrn/DbsNex/actions/workflows/ci.yml)
[![Release](https://github.com/sanyzrn/DbsNex/actions/workflows/release.yml/badge.svg)](https://github.com/sanyzrn/DbsNex/actions/workflows/release.yml)
[![Nightly stress](https://github.com/sanyzrn/DbsNex/actions/workflows/stress.yml/badge.svg)](https://github.com/sanyzrn/DbsNex/actions/workflows/stress.yml)
[![Latest release](https://img.shields.io/github/v/release/sanyzrn/DbsNex-releases?label=release&color=0A84FF)](https://github.com/sanyzrn/DbsNex-releases/releases/latest)
<br>
[![Flutter](https://img.shields.io/badge/Flutter-3.35.5-02569B?logo=flutter&logoColor=white)](./.fvmrc)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](#what-works-today)
[![Languages](https://img.shields.io/badge/languages-فارسی%20%7C%20English-0A84FF)](#what-works-today)
[![Local-first](https://img.shields.io/badge/data-local--first-6E56CF)](./docs/04-architecture.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](./LICENSE)

[Features](#what-works-today) · [Getting started](#getting-started) · [Documentation](#documentation) · [Contributing](#contributing) · [Website](https://DbsStudio.ir/nex/)

</div>

---

Nex is the inbox for your mind. Instead of asking you to choose a folder, a template or a
Save button, it gets out of your way: tap, capture, done. Organize later, if you ever need to.

> Nex is not a knowledge base, not a project manager, not another Notion or Obsidian. It is
> the fastest possible front door into whatever system you use to think.

| | |
|---|---|
| ⚡ **Capture never waits** | Text, voice, photos, files and checklists, with no Save button anywhere. A note exists the moment it has content. |
| 🔎 **Find in seconds** | SQLite FTS5 full-text search with Persian-aware folding, plus tag, type and date filters. |
| 🌐 **Persian first** | Persian and English, full right-to-left layout, the Persian calendar and Persian digits throughout. |
| 🔒 **Local-first and private** | Your notes live in a database on your device. Encrypted backups, an app lock and a vault. |
| 🔔 **Comes back to you** | One-off and repeating reminders, and recurring items with their own calendar. |
| ✨ **AI that stays optional** | Transcription, OCR, summaries and a grounded assistant — off by default, with a provider you choose. |

Nex ships on Android. The codebase is Flutter, and a Windows desktop target still builds
locally, but its CI and release jobs are paused and no Windows build is published. iOS is
not in progress.

---

## What works today

**Capture** — text, voice, photo and arbitrary files. No Save button anywhere: every
capture is committed the moment it exists. Photos go through a crop step on the way in.
Files shared to Nex from another app land the same way as ones picked inside it.
On Android, notes are written in the phone's own text editor, so a note in two languages
keeps each line's direction while it is edited, with the system's selection handles and
menu ([ADR-037](./docs/10-decisions.md#adr-037--text-a-person-writes-is-edited-in-the-platforms-own-editor-on-android)).

**Timeline** — one reverse-chronological stream, no folders, grouped under date headings
that fold (pinch the timeline to fold or open them all), and once you scroll past the top
the day of the note under your thumb stays named under the filters. Cards are a fixed
height in one of three sizes (compact, standard, easier to read), so the list stays even,
and a tapped card rises into its note the way the assistant does. Swipe an edge for
delete or add-tag; hold a card for pin, copy, edit, remind and delete — or **Select**, which
picks several notes at once and swaps the dock for a bar that tags, threads, pins, shares,
copies or deletes them together, with one Undo. Up to five notes can be pinned to the top. Long notes open folded,
with **More** to read the rest. A note converts only one way — to a Markdown file — while
any file that is mostly words (text, Word `.docx`/`.doc`, `.odt`, `.rtf`, HTML, EPUB, CSV,
code, older Windows-1256 Persian text) converts into an editable note.

**Find** — SQLite FTS5 full-text search, plus tag, content-type and date filters with
tappable chips beside the search field (the `tag:`/`type:` operators still work in the
field itself). A search that matches nothing offers the nearest thing you actually wrote
rather than an empty box.

**Organize later** — tags with free-form colours, a tag manager that renames, merges and
deletes, and a trash that holds deleted notes for 30 days.

**Recurring** — things that come back round (rent, insurance, a tablet every eight hours)
live on a page of their own from the home dock, not on the timeline. It opens on how many
are overdue, due today and due this week (each one a filter), payments in the next 30 days,
and a list or a calendar, and each one is set up on a full page; several weekdays, a day of the month or its last day, with real Persian-calendar
monthly and yearly repeats; snooze or skip one occurrence, completion history with notes
and Undo, templates, and optional amounts totalled per currency for the next 30 days.

**Come back to it** — a reminder on any note, one-off or repeating, and an optional daily
nudge at an hour you pick. Both go through the OS scheduler, and when Android refuses to
schedule one — exact alarms off, notifications denied, battery optimisation — the app says
so in the OS's own words rather than failing quietly. A test-notification row in Settings
splits "Nex never sent it" from "my phone swallowed it", and deleting, restoring or editing
a note keeps its alarms exactly as honest as the notes themselves.

**Your data stays yours** — export and import a full archive, automatic throttled local
backups you can prune by hand, an automatic daily copy into a folder you choose (on the
phone, or one a cloud app provides) that says why when it cannot write there, and a storage breakdown that tells you what is using space.
A **complete backup** adds settings and service keys (encrypted with a generated recovery
code), optionally the offline model and the private vault. An interrupted restore rolls
back on the next launch, and unfinished edits in most editors survive the app being
killed.

**Private tools** — a compact Tools page at the left of the home dock holds passwords, bank cards and private saved messages behind device authentication. One unlock opens every private tool and lasts two minutes after the last touch, including time spent in another app; leaving the app always hides the contents. Every field is shown and copyable on the list itself, bank cards take a colour of their own and show their CVV2, each page can be cleared at once, and there is a standalone password generator and a Chrome / Google Password Manager CSV import that brings in every readable row and lists the rest by line. Vault data is excluded from notes, AI and ordinary library backups; encrypted vault export is an explicit option in Complete app backup.

**Intelligence, optional and off by default** — transcription, OCR, summarization, tag
suggestions, semantic search and related notes, each behind its own switch, against a
provider you configure and can test, plus an assistant you can actually talk to about what
you have written, opened by holding the capture button, that can read a tag's or a thread's notes and act on several notes at once. Its tone is yours to set, including one you write yourself. It is the only
part of Nex that can send a note off the device, it says so before it is switched on, and
cloud requests may include your preferred name and selected note context. With only the offline model enabled, generation stays on the device. See [`docs/09-ai.md`](./docs/09-ai.md).

**Home-screen widgets** — Capture, Timeline (with a row that starts a note, voice note, photo or
checklist in one tap) and Recap widgets on Android that follow the
app's language and accent, and stay private while the app lock is on.

**Persian calendar** — optional Solar Hijri dates for display and every date picker,
independent of the interface language.

**Appearance** — light, dark and system modes with whole-app Classic, Paper, Autumn, Rose atelier, Forest, Isfahan turquoise, Saffron, Midnight, Deep sea and Graphite palettes, custom accents, text size and card size; five of the palettes add a faint motif of their own along the bottom of the screen. A change of look opens out as a circle from the tap that asked for it. The Nex logotype is the app icon and the mark on notifications, the Quick Settings tile and the widget; the opening animation keeps the octopus. In-app notices are one capsule that drips out of the top edge (a "gooey" metaball effect, `packages/ui/lib/widgets/nex_gooey.dart`). Liquid Glass is temporarily disabled by owner request; its implementation is retained. Reduce-motion support and 48px minimum action targets remain.

**Feedback** — a compose sheet with a category and an optional reply address, relayed to
Telegram by a separate Cloudflare Worker (`apps/feedback-worker`). It stays unavailable
until that Worker is deployed and its URL is set for release builds.

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
  client/           Flutter app — the product. Android ships; Windows builds, unreleased.
  backend/          Node + PostgreSQL sync API. Built and tested, not deployed until 2.0.
  feedback-worker/  Cloudflare Worker that relays in-app feedback to Telegram.
packages/
  core/             Domain models, ports, services. Pure Dart, no Flutter.
  data/             SQLite repository, schema, sync client. Pure Dart.
  ui/               Design tokens and shared widgets. Flutter.
  ai/               Cloud AI providers, and the removable on-device runtime.
spec/               Language-neutral fixtures both Dart and TypeScript read.
docs/               Product, architecture, design and decision records.
  brand/            The designer's logo and icon artwork the app's pictures are made from.
tools/              Icon and brand generators, CI helper scripts.
```

Two boundaries are load-bearing and are asserted in CI rather than agreed by convention:
`core` and `data` carry **zero Flutter dependency** (the `dart-packages` job never installs
Flutter — that is the assertion), and the on-device AI runtime in `packages/ai` can be
**deleted outright** without breaking anything else ([ADR-035](./docs/10-decisions.md#adr-035--the-ai-provider-layer-lives-in-packagesai-the-on-device-runtime-is-the-removable-half)).

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

`make check` runs the analyze and test part of CI that a contributor can run locally.
It is not the whole pipeline: CI also builds the Android app (including the release App
Bundle of the `ai` flavor on pull requests that touch the Android build), runs the boundary
and deletion proofs, merge conformance and the live sync matrix. Run it before pushing.

```bash
make check          # every target below
make check-dart     # core, data — analyze + test, no Flutter
make check-ai       # packages/ai — needs Flutter
make check-ui       # packages/ui
make check-client   # apps/client
make check-backend  # typecheck, lint, test
make check-worker   # apps/feedback-worker — typecheck + test
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
| [`08-roadmap.md`](./docs/08-roadmap.md) | Phase 1 → 2 → 3 sequencing |
| [`09-ai.md`](./docs/09-ai.md) | What the intelligence layer may and may not do |
| [`10-decisions.md`](./docs/10-decisions.md) | Decision log (`ADR-0nn`) — why things are the way they are |
| [`11-roadmap-2.0.md`](./docs/11-roadmap-2.0.md) | What release 2.0 should be, open items, and what has shipped release by release |
| [`13-sponsor-card.md`](./docs/13-sponsor-card.md) | Publishing the timeline's one sponsor card (`banner.example.json`) |
| [`brand/`](./docs/brand) | Logo, logotype, icon and splash artwork; `tools/generate_brand_assets.py` builds the app's pictures from it |

The numbering has gaps because several documents were build-time scaffolding — a phased
build prompt, agent handoff prompts, an outstanding-work tracker, audit reports, a static
HTML mockup and a duplicate of this file — and were removed once the work they described
was finished; what is still open is in `11-roadmap-2.0.md`. The remaining numbers are stable
because roughly ninety code comments point at them.

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
