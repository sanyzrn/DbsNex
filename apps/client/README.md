# apps/client — Nex Flutter client

The Nex app: one Flutter target that builds to **Android** (shipped) and
**Windows** (builds, not released) — see ADR-024. What it does is in the
root [`README.md`](../../README.md); how it is built is in [`docs/`](../../docs).

`lib/` holds the screens, widgets and platform services; `android/` holds the
native parts (the share and capture entry points, widgets, the native text
editor of ADR-037); `assets/` holds the fonts, guide, changelog and brand
pictures (generated from `docs/brand/` by `tools/generate_brand_assets.py`).

## Platform folders (`android/`, `windows/`)

Generated with:

```bash
cd apps/client
flutter create --platforms=android,windows --project-name nex_client .
```

`flutter create` on an existing directory only adds the missing platform
folders; it leaves `lib/`, `test/` and `pubspec.yaml` in place.

## Run

```bash
flutter pub get
flutter run                # Android device / emulator
flutter run -d windows     # Windows desktop
```

## Verify

```bash
flutter analyze --fatal-infos
flutter test
```

## Note AI workspace (2.0.6)

`lib/screens/note_detail/detail_ai_panel.dart` keeps explicit actions and results
above the note content. `widgets/translate_sheet.dart` supports both the inline
workspace and existing modal callers. Caption replacement uses a compare-and-set
through the database worker; append always reads the latest stored caption.
Similar-note UI and retrieval are paused with `nexRelatedNotesAvailable`, without
erasing the user's preference or disabling semantic search.

Keep `pubspec.yaml`, `lib/app_version.dart`, both root changelogs and their bundled
copies in `assets/` in sync. The tests check this and the 800-line Dart file limit.
Run widget/golden tests on Linux with the Flutter version pinned in CI. Native
Android editor and frame timing checks still require a device.

Future work is tracked in [`docs/11-roadmap-2.0.md`](../../docs/11-roadmap-2.0.md);
the filename is historical and does not promise that sync ships in release 2.0.
