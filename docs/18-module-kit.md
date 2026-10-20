# The module kit

> How a module is written outside this repository (by another agent, or
> another person) and added without risk to the rest of the app. Read
> [`17-modules.md`](17-modules.md) first.

## The idea

A module from outside is **one folder of Dart and one folder of tests**.
Everything else is already there:

- adding it and removing it;
- the question about keeping or deleting its data;
- its card on the Modules page and its tile in Tools;
- its storage, and its place in backups.

The folder may import the module API and nothing past it. A test gate
checks that before anything else runs. So a module that is wrong is wrong
inside its own folder, and the worst it can do is show a bad screen. It
cannot:

- read a note, the vault or Cycle;
- open the network or the file system;
- change a setting;
- break the build of any other screen.

## What a module is made of

```
apps/client/lib/modules/<id>/
  module.dart        the class: extends NexStoredModule
  <screen>.dart …    its screens and logic, as many files as it needs
  README.md          what it does, its records, its words, guide and changelog lines
apps/client/test/modules/<id>/
  <id>_test.dart …   its own tests
```

`<id>` is lower-case letters, digits and `_` (`smoke_free`, `parking`). The
folder name and the module's `id` are the same.

### `module.dart`

```dart
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'parking_screen.dart';

class ParkingModule extends NexStoredModule {
  const ParkingModule();

  @override
  String get id => 'parking';

  @override
  IconData get icon => Icons.local_parking_outlined;

  @override
  NexHue get hue => NexHue.sky;

  @override
  NexModuleStrings get strings => parkingStrings;

  @override
  Widget screen(NexModuleStore store) => ParkingScreen(store: store);
}
```

It defines nothing else. The title, tagline, about text and chips come from
`strings`, and adding and removing come from the base class.

### Words: `NexModuleStrings`

A module's words stay in the module, in both languages: two maps with the
same keys.

- **Required keys:**
  - `title`, `tagline` and `about`;
  - `point1` to `point4`, at least two of them. These are the chips on its
    card.
- **In a widget:** `strings(context, 'key')`.
- **With an argument:** `strings(context, 'count', {'count': 3})`. Numbers
  given as arguments come out in Persian digits on the Persian side.
- **Choosing a calendar:** `NexModuleStrings.persian(context)` says whether
  the app is showing Persian.

### Storage: `NexModuleStore`

The only storage a module has. Records are JSON objects filed under a
**kind** that the module chooses (`spot`, `word`, `receipt`) and an **id**.

| Call | |
|---|---|
| `list(kind)` | Every record of a kind, newest first, as `ModuleRecord`s (`id`, `body`, `updatedAt`). |
| `get(kind, id)` | One record's fields, or null. |
| `put(kind, id, body)` | Saves, replacing what was there. |
| `delete(kind, id)` | |
| `newId()` | A new unique, time-ordered id. |
| `changes` | Fires after this module's records change. A list screen listens to it. |

Values are what JSON holds. A date is stored as `toIso8601String()`.
Records are:

- carried in every backup;
- never searched, embedded, shown on the timeline or read by the assistant;
- deleted together when someone removes the module and chooses to delete.

### What the API gives

`module_api.dart` exports:

- `package:nex_ui/nex_ui.dart`: the tokens `NexSpacing`, `NexRadius` and
  `NexMotion`, `NexPageRoute`, the colour helpers, and the shared widgets;
- the shelf widgets (`NexPanel`, `NexShelfHeading`, `NexHue`, …);
- `NexMoreDetails` (`module_form.dart`) — the optional half of a form behind
  one button;
- `NexModuleHero` and `nexModuleAccent` (`module_hero.dart`) — the one hero
  that opens a module's home page, in the module's own colour;
- `nexShowSheet`, `nexShowDialog` and `NexDialogBody`;
- `NexTextField`, the shared multiline editor (native on Android);
- `nexPickModuleDate`, `NexModuleDateEntry` and `nexModuleDateLabel`, using the saved calendar while retaining civil dates at the storage boundary;
- `NexModuleReminderControl` and store reminder methods for explicit one-time OS alerts. Only available, installed modules may schedule them; removing a source record, archiving it or removing the module cancels its alarms. Requests are restored at launch. All stored modules remain Soon and silent in 2.1.3;
- `AppLocalizations`, for the shared words such as `cancel`;
- the module classes above.

Flutter's `material`, `widgets`, `foundation`, `animation`, `painting`,
`gestures` and `rendering` libraries, and `dart:async`, `math`, `convert`,
`collection` and `ui` may be imported too.

## The gate: `test/module_kit_test.dart`

For every folder under `lib/modules/`, the gate checks five things:

1. **Imports.** Every import is one of those above, or a file inside the
   module's own folder.
2. **Forbidden code.** No file:
   - overrides `open`, `turnOn`, `turnOff` or `isOn`;
   - names `NexServices` or `NexPreferences`;
   - opens a platform channel;
   - calls `showModalBottomSheet` or `showDialog` (it uses `nexShowSheet` and
     `nexShowDialog`).
3. **Files.** It has a `README.md`, and tests under `test/modules/<id>/`.
4. **Registry.** It is in `nexModules`.
5. **Words.** Both languages have the same keys, every required key is there,
   and no value is empty.

The gate also runs the worked example, `test/module_kit/tally/`: a tally
counter that is added, used, removed keeping its data, and removed deleting
it. Copying that is the fastest way to start.

## What a module cannot do yet

The following are deliberately outside the API until a module needs them:

- location;
- the camera and photos;
- network access;
- home-screen widgets;
- assistant tools;
- links into notes.

A module that needs one of them builds everything else, and lists the need
under **Platform requests** in its README. That API is then added here, by
the maintainers, in its own pull request, and the module uses it from then
on. The platform grows only by what a real module asked for.

## Adding a module someone else wrote

1. Unzip it into `apps/client/`. `git status` must show only
   `lib/modules/<id>/` and `test/modules/<id>/`; anything else is refused.
2. Add one line to `nexModules` in `module_registry.dart`, with its import.
3. Run the gate and the module's tests:

   ```
   flutter test test/module_kit_test.dart test/modules/<id>
   ```

   Then run the full checks (`make check-dart`, `flutter analyze`,
   `flutter test`).
4. Read the diff as a review: design language, both languages, light and
   dark, large text, and that it does what its README says.
5. Take the guide paragraph and the changelog lines from its README into the
   guide and the changelogs. Remove it from `module_plans.dart` if it was
   listed there.

The prompt to give the agent that writes a module is
[`prompts/11-module-builder.md`](prompts/11-module-builder.md).

Draft writes have their own `draftChanges` stream; `changes` is for saved data.
Journal and `__recovery` writes do not wake list readers. Draft helpers coalesce
typing for 250 ms and flush on close; final save/discard waits for in-flight
writes before cleanup. Unknown or malformed journals are copied to
`__recovery` before leaving the active queue; raw undecodable database bodies
are preserved there byte-for-byte. Never replay a partly validated journal.
