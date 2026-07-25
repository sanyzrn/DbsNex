# apps/client — Nex Flutter client

One Flutter app target that builds to **Android**, **Windows** and (later) iOS
— see ADR-024. Phase 0 contains an empty screen and nothing else.

## Platform folders (`android/`, `windows/`) are not committed yet

The generated platform shells could not be produced in the authoring
environment (no Flutter SDK available — see the Phase 0 report). Materialise
them once, in a checkout that has Flutter installed:

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
