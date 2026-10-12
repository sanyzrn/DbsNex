# Task: build one Nex module, as a drop-in folder

You are a senior Flutter engineer. You will build **one module** for Nex: a
self-contained optional feature that the maintainers add to the app by
copying in your folder. What the module is comes at the end of this prompt,
under **The module**.

Your work is accepted only if it passes the module kit's gate unchanged and
touches nothing outside the module's own two folders. Read all of this
before you write any code.

## Getting the code

- **Repository:** <https://github.com/sanyzrn/DbsNex> (public). Work from
  `main`.
- **You will be in one of two setups.** Work out which one before you start,
  and name it in your hand-off.
  - **Your own cloud workspace:**
    `git clone https://github.com/sanyzrn/DbsNex.git && cd DbsNex`
  - **The owner's Windows PC, with a shared folder:**
    - Run `git config --global core.longpaths true` first.
    - Clone into that folder.
    - Use PowerShell for the commands.
- **Toolchain:** Flutter 3.35.x (Dart 3.9). In `apps/client`, run
  `flutter pub get` first.
- **Read-only towards GitHub.** Do not push, open pull requests or file
  issues. Your hand-off is the zip described below.

## What Nex is, and what a module is

Nex is a local-first, offline-first personal capture app for Android, with
Persian as its first language (right to left) and English as its second.
It holds people's notes, passwords, bank cards and health data, and its
promise is that **nothing leaves the phone unless the person asks**.

Modules are optional features. A module is not part of the app until
someone adds it on **Tools → Modules**. Read these files in the repository:

- `docs/17-modules.md`: the module platform.
- `docs/18-module-kit.md`: **the rules you are building against.** Read it
  twice.
- `docs/16-design-language.md`: how every Nex screen looks and behaves.
- `apps/client/lib/modules/module_api.dart` and the files it exports:
  everything you may use.
- `apps/client/test/module_kit/tally/` and `apps/client/test/module_kit_test.dart`:
  the worked example, and the gate.

## The rules

### 1. Where you may write

- `apps/client/lib/modules/<id>/`: your code, plus `README.md`.
- `apps/client/test/modules/<id>/`: your tests.

You may write nothing else.

- To run the gate locally, add your module to `nexModules` in
  `apps/client/lib/modules/module_registry.dart`, and **leave that change out
  of your hand-off**. The maintainers add that line themselves.
- Do not edit:
  - the ARB files;
  - `pubspec.yaml`;
  - any other screen;
  - the module API;
  - the gate.
- If you think one of them needs to change, say so under
  **Platform requests**.

### 2. Imports

Only these:

- `package:nex_client/modules/module_api.dart`;
- these Flutter libraries:
  - `package:flutter/material.dart`, `widgets.dart` and `foundation.dart`;
  - `animation.dart`, `painting.dart`, `gestures.dart` and `rendering.dart`;
- `dart:async`, `dart:math`, `dart:convert`, `dart:collection` and `dart:ui`;
- files inside your own folder.

There are no new packages, no `dart:io`, no `package:http`, no platform
channels, and no files of the app outside the API.

### 3. The class

`module.dart` defines one class that `extends NexStoredModule`. It
overrides only:

- `id` (the same as the folder name);
- `icon`;
- `hue` (one of `NexHue`);
- `strings`;
- `screen(store)`.

Do not override `open`, `turnOn`, `turnOff` or `isOn`. Adding, removing and
deleting the data are done for you.

### 4. Data

Use only `NexModuleStore`: `list`, `get`, `put`, `delete`, `newId` and
`changes`.

- Choose clear record kinds and fields, and document them in the README.
- Store dates as `toIso8601String()`.
- Store money and weights as integers in the smallest unit (rials, tenths of
  a gram, or whatever fits), never as floating-point.
- Read old records defensively. A field may be missing, because a later
  version of your module may add fields.

### 5. Words

Every word a person sees comes from your `NexModuleStrings`:

- the same keys in `en` and `fa`;
- the required keys: `title`, `tagline`, `about`, and `point1`–`point4` (at
  least two);
- Persian that is natural, written for a Persian reader, not translated word
  by word;
- numbers in Persian digits on the Persian side. Pass numbers as arguments
  (`{count}`), so the module strings convert them.
- Dates in Persian need the Persian (Jalali) calendar. If you cannot do that
  with what the API gives you, show relative dates ("3 days ago"), and list
  the need under Platform requests.

### 6. Design

Follow `docs/16-design-language.md`:

- sheets open with `nexShowSheet`, never `showModalBottomSheet`;
- pages are pushed with `NexPageRoute`;
- spacing and corners come from `NexSpacing` and `NexRadius`;
- colour comes from the theme's `ColorScheme`, plus your module's `hue` via
  `hue.of(Theme.of(context).brightness)`. There are no other hard-coded
  colours;
- every screen works in Persian (RTL) and English (LTR), light and dark,
  and at the largest text size without overflow;
- use start/end, not left/right (`EdgeInsetsDirectional`,
  `AlignmentDirectional`);
- touch targets are at least 48 dp, and every icon-only button has a
  tooltip;
- an empty state says what to do first, and acts: it carries the button that
  does it.

### 7. Behaviour

- **Nothing is lost.** Saving happens as the person types or taps, with no
  Save button that can be forgotten.
- **Deleting a record can be undone** for a few seconds, with a SnackBar and
  an Undo action.
- **Nothing is sent anywhere.** The module works fully offline.
- **No telemetry, no ads, and no links out** unless they are the point of
  the module.
- **Calm and honest.** No guilt, no streak-shaming, and no medical, legal or
  financial claim that the module cannot back. Say what a number is based
  on.

### 8. Code quality

- No file is longer than 400 lines. Split screens into widgets.
- Comments explain *why*, in full sentences, as the rest of the code base
  does.
- Business logic, such as calculations, predictions and grouping, goes in
  plain Dart classes with no widgets, so it can be unit-tested.
- `flutter analyze --fatal-infos` passes, and the code is formatted with
  `dart format`.

### 9. Tests

In `test/modules/<id>/`:

- unit tests for every calculation, including edge cases: zero, empty,
  very large values, and a record missing a field;
- widget tests for:
  - the empty state;
  - adding a record;
  - editing it;
  - deleting it, and undoing the delete;
  - the screen in Persian (`locale: Locale('fa')`), with no overflow at text
    scale 2.0.

  Use `NexTestHarness` from `test/support/nex_harness.dart`, as
  `test/module_kit_test.dart` does.
- All of them pass, together with the gate:

```
cd apps/client
flutter test test/module_kit_test.dart test/modules/<id>
flutter analyze --fatal-infos
```

Then run the whole client suite once (`flutter test`), to show that you
broke nothing.

### 10. The module's README

`apps/client/lib/modules/<id>/README.md`, with these sections:

1. **What it does:** a short paragraph, then the screens one by one.
2. **Records:** each kind, with its fields and their types.
3. **Decisions:** what you chose and why, especially where the brief was
   open.
4. **Guide:** the paragraph for the in-app guide, in English and in Persian.
5. **Changelog:** one line in English and one in Persian, in the style of
   `CHANGELOG.md` and `CHANGELOG.fa.md`.
6. **Platform requests:** what you needed and the API did not give you, and
   how the module behaves without it. Write "None" if there is nothing.
7. **Checks:** the exact commands you ran and the end of their output.

## Hand-off

One zip, named `<id>-module.zip`. Its paths are relative to `apps/client/`,
so unzipping it there adds your two folders and nothing else:

```
lib/modules/<id>/…
test/modules/<id>/…
```

In your reply, give:

- the setup you were in;
- the commit of `main` you built on;
- the README's **Platform requests** and **Checks** sections;
- screenshots of the main screen, in Persian dark and English light, if you
  can take them.

## Before you hand off, check each of these

- [ ] Only two folders, and the registry line is not included.
- [ ] The gate and your tests pass. `flutter analyze` is clean.
- [ ] There are no imports outside the allowed list.
- [ ] Every word is in both languages, and the Persian reads naturally.
- [ ] RTL, dark mode and text scale 2.0 have been looked at, not assumed.
- [ ] Deleting a record can be undone, and nothing is sent anywhere.
- [ ] The README has all seven sections.

## The module

> The owner writes the idea here: what it is for, who it is for, and
> anything it must or must not do. Where the idea is open, decide, and
> explain your decision under **Decisions** in the README.
