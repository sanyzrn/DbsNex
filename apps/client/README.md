# apps/client — Nex Flutter client

One Flutter app target that builds to **Android**, **Windows** and (later) iOS
— see ADR-024. Phase 0 contains an empty screen and nothing else.

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
