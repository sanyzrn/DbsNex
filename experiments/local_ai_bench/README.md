# local_ai_bench

Throwaway feasibility harness for Phase 0 of the offline-AI roadmap
(`../../docs/09-ai.md`): does a local GGUF model run acceptably on real
Android hardware, before anything is designed on top of it.

A standalone project, not part of `apps/client`. `apps/client` and every
package under `packages/` are checked by CI (the "packages/ai deletion
proof" job) to never depend on `nex_ai` directly, so this experiment lives
outside both — free to depend on `nex_ai` without touching that guarantee.

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
was written from a sandbox with no route to huggingface.co, so none of this
was checked live.

Get the `.gguf` file onto the test device, e.g.:

```
adb push gemma-3-4b-it-Q4_K_M.gguf /sdcard/Download/
```

## 3. Run it

```
cd experiments/local_ai_bench
flutter run -d <device-id>
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
