/// Nex — Core domain layer.
///
/// Pure Dart. Zero Flutter dependency. Zero storage dependency.
///
/// Dependency rule (06-development.md): apps/* -> packages/core, and
/// packages/data -> packages/core. Core sits at the bottom and depends on
/// nothing in this repository.
///
/// This library used to contain:
///
///   export 'package:nex_data/nex_data.dart';
///
/// which handed every caller the whole persistence layer — NexDatabase,
/// NoteRepository, SyncClient and the raw SQLite types — and made the
/// documented layering decorative. It also dragged sqlite3 FFI, archive and
/// http into packages/ui, a package that renders widgets.
library nex_core;

// Domain models.
export 'models/note.dart';
export 'models/tag.dart';

// Ports: the contracts the app and the data layer agree on.
export 'ports/media_picker.dart';
export 'ports/note_repository.dart';
export 'ports/sync_port.dart';

// Domain services.
export 'ai/ai_adapter.dart';
export 'ai/ai_adapter_binding.dart';
export 'ai/ai_capabilities.dart';
export 'ai/enrichment_service.dart';
export 'ai/on_device_ai_adapter.dart';
export 'capture/capture_service.dart';
export 'sync/field_aware_merger.dart';
