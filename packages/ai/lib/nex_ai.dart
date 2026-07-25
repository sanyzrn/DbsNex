/// Nex — Optional AI adapters (v3+).
///
/// Structurally optional: this package must remain removable without touching
/// Core, Data or UI (`06-development.md` → Coding Principles #5). Nothing on
/// the capture path may import it.
///
/// Phase 0 scaffold: no adapter interface is declared yet — the `AIAdapter`
/// contract from `06-development.md` is introduced when the AI layer is
/// actually scheduled (v3+), not in Phase 0.
library nex_ai;

/// Package identity. Used by the Phase 0 scaffold test.
const String packageName = 'nex_ai';
