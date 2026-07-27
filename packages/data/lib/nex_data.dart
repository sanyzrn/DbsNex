/// Nex — Local-first data layer.
///
/// Pure Dart. Zero Flutter dependency (see `06-development.md`).
library;

/// The domain models moved to packages/core, where the ports that describe them
/// already lived. They are re-exported here so callers of the storage layer
/// still get the types its methods traffic in from a single import.
///
/// This direction is legal and is the whole point of the refactor: data depends
/// on core. What was forbidden — and what `nex_core.dart` used to do — is the
/// reverse.
export 'package:nex_core/nex_core.dart'
    show
        Note,
        NoteEmbedding,
        NoteType,
        SearchFilters,
        SyncPort,
        SyncResult,
        SyncState,
        Tag,
        newUuidV7,
        sha256OfBytes,
        sha256OfFile;

export 'repositories/note_repository.dart';
export 'schema/database.dart';
export 'sync_client/sync_client.dart';
