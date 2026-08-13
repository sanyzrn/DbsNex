import '../models/memory_record.dart';

/// Storage contract for the local memory/profile store (09-ai.md — Phase 2).
///
/// Declared in core so domain services depend on a behaviour rather than on
/// SQLite, the same split `NoteRepository` already draws.
/// `packages/data` provides the implementation (`SqliteMemoryRepository`).
/// Every method is synchronous for the same reason `NoteRepository`'s are:
/// `package:sqlite3` is a synchronous FFI binding, so the repository runs
/// inside the database isolate alongside the services declared here.
abstract interface class MemoryRepository {
  MemoryRecord insert(MemoryRecord record);

  MemoryRecord? getById(String id, {bool includeDeleted = false});

  List<MemoryRecord> listByKind(MemoryKind kind, {bool includeDeleted = false});

  MemoryRecord update(MemoryRecord record);

  void softDelete(String id);
}
