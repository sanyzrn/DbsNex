/// Nex — Local-first data layer.
///
/// Pure Dart. Zero Flutter dependency (see `06-development.md` → Folder
/// Structure). SQLite/FTS5, repositories and the sync client live here.
///
/// Phase 0 scaffold: this package intentionally contains **no schema and no
/// repository code**. Phase 1 adds:
///   - `lib/schema/`       → Note (UUIDv7 id, created_at, updated_at,
///                            deleted_at, device_id, rev, media_hash), Tag
///   - `lib/repositories/` → note/tag repositories over SQLite + FTS5
///   - `lib/sync_client/`  → dormant in v1, active in v2
library nex_data;

/// Package identity. Used by the Phase 0 scaffold test to prove the package
/// resolves and executes under plain `dart test`.
const String packageName = 'nex_data';
