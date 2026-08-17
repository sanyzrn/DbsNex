/// Nex — Core domain layer.
///
/// Pure Dart. Zero Flutter dependency. Zero storage dependency.
///
/// Dependency rule (06-development.md): apps/* -> packages/core, and
/// packages/data -> packages/core. Core sits at the bottom and depends on
/// nothing in this repository.
///
/// This library used to re-export packages/data wholesale, which handed every
/// caller the whole persistence layer — the database handle, the SQLite
/// repository, the sync client and the raw sqlite3 types — and made the
/// documented layering decorative. It also dragged sqlite3 FFI, archive and
/// http into packages/ui, a package that renders widgets. The domain models now
/// live here, where the contracts describing them already lived.
library;

// Domain models.
export 'models/checklist.dart';
export 'models/memory_record.dart';
export 'models/note.dart';
export 'models/note_embedding.dart';
export 'models/search_filters.dart';
export 'models/tag.dart';

// Identity and content hashing.
export 'ids.dart';

// Ports: the contracts the app and the data layer agree on.
export 'ports/media_picker.dart';
export 'ports/memory_repository.dart';
export 'ports/note_repository.dart';
export 'ports/sync_port.dart';

// Domain services.
export 'ai/ai_adapter.dart';
export 'ai/ai_adapter_binding.dart';
export 'ai/ai_capabilities.dart';
export 'ai/chat_adapter.dart';
export 'ai/chat_adapter_binding.dart';
export 'ai/chat_scope_policy.dart';
export 'ai/entitlement.dart';
export 'ai/enrichment_service.dart';
export 'ai/import/context_import_draft.dart';
export 'ai/on_device_ai_adapter.dart';
export 'ai/tools/nex_tool_registry.dart';
export 'ai/tools/tool_call.dart';
export 'ai/tools/tool_definition.dart';
export 'ai/tools/tool_executor.dart';
export 'capture/capture_service.dart';
export 'sync/field_aware_merger.dart';
