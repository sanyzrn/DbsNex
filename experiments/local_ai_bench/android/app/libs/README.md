# `libs/llama-cpp-dart.aar` — not committed

This harness needs the native llama.cpp runtime that `lib/main.dart` loads
through the `llama_cpp_dart` package. That package ships **no native
binaries** in its Dart package — they're distributed separately as prebuilt
release assets.

1. Go to <https://github.com/netdur/llama_cpp_dart/releases> and grab
   `llama-cpp-dart.aar` (CPU + mtmd, arm64-v8a) from the release matching the
   pinned version in `../../../../packages/ai/pubspec.yaml` (`0.9.0-dev.10`
   at the time this was written — a newer release is probably fine too, but
   re-check the pubspec pin first).
   - Use `llama-cpp-dart-hexagon.aar` instead if you specifically want to
     test the Snapdragon Hexagon NPU / OpenCL path — the CPU AAR is the
     right first measurement, since it's the floor every arm64 device can
     hit, not just Snapdragon ones.
2. Put the file here, named exactly `llama-cpp-dart.aar`.
3. Build/run as usual. `android/app/build.gradle.kts` only adds it as a
   dependency if this file exists.

**arm64-v8a only.** This AAR has no armeabi-v7a or x86_64 binary. On other
ABIs the bench screen's model load will fail to find `libllama.so` — that's
expected, not a bug to chase; the real feature will need the same runtime
check before ever offering local AI on a device.
