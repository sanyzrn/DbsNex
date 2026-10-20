# Modules

> How optional features join Nex without weighing on the people who never
> want them. Decision: ADR-040.

## The idea in one paragraph

A **module** is a feature that ships inside the app but does not exist
until someone adds it. Off, it has no tile, no menu entry, no notification,
no background work, no widget and no assistant tool. It is as if it were
not installed. People add and remove modules on one page, **Tools →
Modules**: each module's card says what it is, in a few lines, and how its
data is kept. Removing a module asks once whether to keep its data, so that
adding it back finds everything where it was, or to delete it.

## Rollout (paused from 2.1.1, resumed one module at a time)

Cycle, Habits, Price Lens, Lent & Borrowed, Quit Habits and Birthdays &
occasions are available (2.1.11–2.1.13), listed in `nexAvailableModuleIds`. The other seven stored add-ons remain compiled
and registered but appear as Soon plans without add/open/remove controls.
Their records and saved installation flags are unchanged. `NexModule.available`
controls rollout independently of `isOn`; `nexModulesOn` applies both gates,
so Tools and pinned tools cannot open a paused module. Re-enable each add-on
only after its review. Newly planned modules also use the Soon badge.

## Two layers

| | Layer 1: modules | Layer 2: tracker templates |
|---|---|---|
| What it is | Dart code behind the `NexModule` contract | A JSON description run by a tracker engine in the app |
| Good for | Features with their own screens and logic: Cycle, a planner, a quit-smoking companion with the assistant | Simple trackers: water, mood, medicine, a habit, a streak |
| How it arrives | In the app update, off until added | In the app, or fetched from a signed catalogue later |
| Status | **Available from 1.99.60** (Cycle is the first) | Planned |

No layer ever downloads executable code. Flutter on Android cannot load it,
the stores Nex ships through do not allow it, and it would break the
promise that nothing reaches the phone unless asked.

## Two kinds of layer-1 module

- **Built-in modules** implement `NexModule` directly and may use anything in
  the app. Only Cycle is one, because it predates the platform and has its own
  tables, reminders and widgets.
- **Stored modules** extend `NexStoredModule`. Every module after Cycle is one.
  - It is one folder, `lib/modules/<id>/`, that sees only
    `lib/modules/module_api.dart`.
  - It keeps its data in its own `NexModuleStore`: JSON records in the shared
    `module_records` table, bound to its id.
  - Adding, removing, the keep-or-delete question and deleting the data are
    done for it.
  - A test gate (`test/module_kit_test.dart`) holds it to that, which is what
    lets a module be written by another agent and dropped in. See
    [`18-module-kit.md`](18-module-kit.md).

## The contract (layer 1)

`apps/client/lib/modules/nex_module.dart`:

| Member | What it is for |
|---|---|
| `id` | Stable and lower-case (`cycle`). It keys the preference and the tests. |
| `title`, `tagline`, `about`, `points` | The words on the module's card, from the ARB files. |
| `icon`, `hue` | The module's glyph and its `NexHue`: the same colour on its card and its Tools tile. |
| `available` | Whether this release permits use of the module, independent of saved installation. |
| `isOn(preferences)` | The saved installation choice; effective availability also requires `available`. |
| `turnOn(context, …)` | Adding it. Applies whatever it needs: reminders, its first-run questions. |
| `turnOff(context, …)` | Removing it. Asks keep-or-delete, cancels its reminders and work. Resolves to `false` if the person backed out. |
| `open(services, preferences)` | The module's own screen, opened from its tile in Tools. |

New modules use the generic preference
`NexPreferences.isModuleOn(id)` / `setModuleOn(id, on)` (`module.<id>.on`).
Cycle keeps its older `cycle.enabled` key, so nobody's Cycle switches off on
update.

Every place a module reaches — Tools tiles, reminders scheduled at launch,
home-screen widgets, the assistant's tools, settings search — asks
`isOn(preferences)` first. Off means **none** of them run.

## Adding a module

A new module is a stored module, built with the module kit
([`18-module-kit.md`](18-module-kit.md)). The steps below are for the rare
built-in one:

1. Write the feature under `lib/screens/<id>/` and its logic under
   `lib/platform/`, as any screen.
2. Implement `NexModule` in `lib/modules/<id>_module.dart`.
3. Add it to `nexModules` in `lib/modules/module_registry.dart`. That alone
   puts its card on the Modules page and, once added, its tile in Tools.
4. Gate everything it does outside its own screen — reminders, widgets,
   assistant tools, launch work — on `isOn`.
5. Give it a data-deletion path, and test both "remove, keep" and
   "remove, delete".
6. Add its guide section and changelog lines, in both languages.

## What is coming

`lib/modules/module_plans.dart` lists the modules that are not built yet.
Each has a name, a line on what it will do and a badge, Soon or Planned, and
they appear under **On the way** on the Modules page with no button. When
one is built, it leaves that list and joins `nexModules`. A row at the foot
of the page opens the feedback sheet, for ideas.

## Where things are

- `lib/modules/nex_module.dart`: the contract.
- `lib/modules/module_registry.dart`: the list of every module.
- `lib/modules/cycle_module.dart`: Cycle as a module.
- `lib/modules/nex_stored_module.dart`, `nex_module_store.dart`,
  `nex_module_strings.dart`: the base every new module extends, its storage
  and its words.
- `lib/modules/module_api.dart`: the one import a stored module may use.
- `lib/modules/module_plans.dart`: what is on the way.
- `lib/screens/modules_screen.dart`: Tools → Modules.
- `packages/data/lib/repositories/module_record_repository.dart`: the records.
- `test/modules_test.dart`: the page, adding and removing, and Tools tiles.
- `test/module_kit_test.dart`, `test/module_kit/tally/`: the gate, and its
  worked example.

### On the way: Persian calendar & prayer times (2.0.9)

`persian-calendar` is a single coming-soon plan: Solar Hijri calendar,
occasions and date conversion, prayer times for a chosen city, optional adhan
alerts and per-prayer settings. It is a catalogue preview only, not an enabled
module: it has no install/open action, location request or scheduled alert yet.
