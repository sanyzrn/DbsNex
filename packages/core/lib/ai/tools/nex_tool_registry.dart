import '../../capture/capture_service.dart';
import '../../models/search_filters.dart';
import '../entitlement.dart';
import 'tool_call.dart';
import 'tool_definition.dart';

/// The tools a chat model may call against Nex's own use cases (09-ai.md —
/// Phase 2, ADR-029).
///
/// Wraps the existing [CaptureService] / [TagService] / [SearchService] —
/// nothing here talks to storage directly. **`create_task` / `create_reminder`
/// are deliberately not registered**: Task/Reminder is not a domain concept
/// anywhere in `packages/core`, `packages/data`, or `apps/backend` yet, and
/// needs its own design/ADR (09-ai.md — Phase 3+) before a tool can call it.
/// Every registered tool requires [AiEntitlement.personalAssistant] — general
/// chat (free) never reaches this registry, per the Free vs. Paid Boundary.
class NexToolRegistry {
  NexToolRegistry({
    required CaptureService captureService,
    required TagService tagService,
    required SearchService searchService,
  }) : _captureService = captureService,
       _tagService = tagService,
       _searchService = searchService {
    _register(_createNoteTool, _handleCreateNote);
    _register(_searchNotesTool, _handleSearchNotes);
    _register(_addTagTool, _handleAddTag);
    _register(_removeTagTool, _handleRemoveTag);
    _register(_listTagsTool, _handleListTags);
  }

  final CaptureService _captureService;
  final TagService _tagService;
  final SearchService _searchService;

  final Map<String, ToolDefinition> _definitions = {};
  final Map<String, ToolResult Function(Map<String, Object?>)> _handlers = {};

  void _register(
    ToolDefinition definition,
    ToolResult Function(Map<String, Object?>) handler,
  ) {
    _definitions[definition.name] = definition;
    _handlers[definition.name] = handler;
  }

  List<ToolDefinition> get definitions =>
      List.unmodifiable(_definitions.values);

  ToolDefinition? definitionFor(String name) => _definitions[name];

  /// Runs [call] with no entitlement check — callers should go through
  /// [GatedToolExecutor] instead, which checks [ToolDefinition.requiresEntitlement]
  /// first.
  ToolResult dispatch(ToolCall call) {
    final handler = _handlers[call.name];
    if (handler == null) {
      return ToolResult.error('unknown_tool: ${call.name}');
    }
    return handler(call.arguments);
  }

  static final _createNoteTool = ToolDefinition(
    name: 'create_note',
    description: 'Create a new text note in Nex.',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'content': {'type': 'string'},
      },
      'required': ['content'],
    },
    requiresEntitlement: AiEntitlement.personalAssistant,
  );

  ToolResult _handleCreateNote(Map<String, Object?> args) {
    final content = args['content'];
    if (content is! String) {
      return const ToolResult.error('missing_argument: content');
    }
    final note = _captureService.submitTextCapture(content);
    if (note == null) {
      return const ToolResult.error('empty_content');
    }
    return ToolResult.ok(note.toJson());
  }

  static final _searchNotesTool = ToolDefinition(
    name: 'search_notes',
    description: "Search the user's notes by keyword.",
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'query': {'type': 'string'},
      },
      'required': ['query'],
    },
    requiresEntitlement: AiEntitlement.personalAssistant,
  );

  ToolResult _handleSearchNotes(Map<String, Object?> args) {
    final query = args['query'];
    if (query is! String) {
      return const ToolResult.error('missing_argument: query');
    }
    final notes = _searchService.search(SearchFilters(query: query));
    return ToolResult.ok(notes.map((n) => n.toJson()).toList());
  }

  static final _addTagTool = ToolDefinition(
    name: 'add_tag',
    description: 'Attach a tag (creating it if needed) to a note.',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'noteId': {'type': 'string'},
        'name': {'type': 'string'},
      },
      'required': ['noteId', 'name'],
    },
    requiresEntitlement: AiEntitlement.personalAssistant,
  );

  ToolResult _handleAddTag(Map<String, Object?> args) {
    final noteId = args['noteId'];
    final name = args['name'];
    if (noteId is! String) {
      return const ToolResult.error('missing_argument: noteId');
    }
    if (name is! String) {
      return const ToolResult.error('missing_argument: name');
    }
    final tag = _tagService.addTag(noteId: noteId, name: name);
    return ToolResult.ok(tag.toJson());
  }

  static final _removeTagTool = ToolDefinition(
    name: 'remove_tag',
    description: 'Detach a tag from a note.',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'noteId': {'type': 'string'},
        'tagId': {'type': 'string'},
      },
      'required': ['noteId', 'tagId'],
    },
    requiresEntitlement: AiEntitlement.personalAssistant,
  );

  ToolResult _handleRemoveTag(Map<String, Object?> args) {
    final noteId = args['noteId'];
    final tagId = args['tagId'];
    if (noteId is! String) {
      return const ToolResult.error('missing_argument: noteId');
    }
    if (tagId is! String) {
      return const ToolResult.error('missing_argument: tagId');
    }
    _tagService.removeTag(noteId: noteId, tagId: tagId);
    return const ToolResult.ok(null);
  }

  static final _listTagsTool = ToolDefinition(
    name: 'list_tags',
    description: "List every tag in the user's library.",
    parametersSchema: const {'type': 'object', 'properties': {}},
    requiresEntitlement: AiEntitlement.personalAssistant,
  );

  ToolResult _handleListTags(Map<String, Object?> _) {
    final tags = _tagService.listTags();
    return ToolResult.ok(tags.map((t) => t.toJson()).toList());
  }
}
