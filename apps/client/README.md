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
flutter analyze
flutter test
```
