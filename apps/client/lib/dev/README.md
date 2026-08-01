# Phase 0 bench harness — running it

`local_ai_bench_main.dart` is a throwaway screen for one question: does a
local GGUF model run acceptably on real Android hardware? See
`docs/09-ai.md` for where this sits in the roadmap. Nothing here ships —
`main.dart` never imports this directory.

## 1. Native library

Get `llama-cpp-dart.aar` onto the device build first —
`android/app/libs/README.md` has the exact steps. Skip this and the app
still builds fine; the bench screen just fails to load a model.

## 2. A model to test

Any instruct-tuned GGUF in roughly the 1–4B parameter range, quantized
around Q4 (`Q4_K_M` or `Q4_0`), is the right starting point — small enough to
plausibly run on a mid-range phone, big enough to be worth measuring. A few
families that were commonly available in GGUF at the time this was written:
Google's Gemma 3 (1B/4B), Qwen2.5 (3B), Microsoft's Phi-3.5-mini. **Verify
current availability and exact repo names on Hugging Face yourself** — this
sandbox has no route to huggingface.co, so none of this was checked live.

Get the `.gguf` file onto the test device, e.g.:

```
adb push gemma-3-4b-it-Q4_K_M.gguf /sdcard/Download/
```

## 3. Run it

```
flutter run -d <device-id> -t lib/dev/local_ai_bench_main.dart
```

In the app: **Pick .gguf** → browse to the file → **Load model** → run one
of the preset prompts or **Run all presets**. Each run appends a line like:

```
tokens=64 ttft=420ms total=3100ms tok/s=23.9 peakRss=1840MB stop=StopEog
```

## 4. What to report back

For each model tried: device model, `tok/s`, `ttft`, `peakRss`, and whether
the phone got noticeably warm over a few consecutive runs (thermal
throttling shows up as `tok/s` dropping run over run, not in any single
number). That's what Phase 0 needs to turn into a go/no-go and a model
shortlist for Phase 2.
