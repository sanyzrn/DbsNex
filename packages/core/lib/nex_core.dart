/// Nex — Core domain layer.
///
/// Pure Dart. Zero Flutter dependency, verified by `dart test` running this
/// package without a Flutter SDK or widget-test harness
/// (see `06-development.md` → Folder Structure, and Phase 0 tasks in
/// `11-build-prompt.md`).
///
/// Phase 0 scaffold: this package intentionally contains **no product logic**.
/// Phase 1 adds pure use cases under:
///   - `lib/capture/`  → submitCapture
///   - `lib/tags/`     → addTag / removeTag
///   - `lib/search/`   → search(query, filters)
///   - `lib/sync/`     → conflict resolution (Phase 2: scalar LWW, tag union-merge)
library nex_core;

/// Package identity. Used by the Phase 0 scaffold test to prove the package
/// resolves and executes under plain `dart test`.
const String packageName = 'nex_core';
