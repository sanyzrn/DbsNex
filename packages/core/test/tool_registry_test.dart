import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// Minimal in-memory [NoteRepository] — packages/core tests must not depend
/// on packages/data's SQLite implementation.
class _FakeNoteRepository implements NoteRepository {
  final List<Note> _notes = [];
  final List<Tag> _tags = [];

  @override
  Note insert(Note note) {
    _notes.add(note);
    return note;
  }

  @override
  Note? getById(String id, {bool includeDeleted = false}) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  @override
  List<Note> listTimeline({int limit = 50, int offset = 0, String? tagId}) =>
      List.of(_notes);

  @override
  List<Note> search(SearchFilters filters) {
    if (filters.query.isEmpty) return List.of(_notes);
    return _notes
        .where((n) => (n.content ?? '').contains(filters.query))
        .toList();
  }

  @override
  Tag upsertTag({required String name, String? color}) {
    final existing = _tags.where((t) => t.name == name);
    if (existing.isNotEmpty) return existing.first;
    final tag = Tag(
      id: newUuidV7(),
      name: name,
      color: color,
      createdAt: DateTime.now().toUtc(),
    );
    _tags.add(tag);
    return tag;
  }

  @override
  void attachTag({required String noteId, required String tagId}) {}

  @override
  void detachTag({required String noteId, required String tagId}) {}

  @override
  List<Tag> listTags() => List.of(_tags);

  @override
  void setTagColor({required String tagId, String? color}) {}

  @override
  void setTranscriptText(String noteId, String text) {}

  @override
  void setOcrText(String noteId, String text) {}

  @override
  void setSummaryText(String noteId, String text) {}

  @override
  void setEmbedding(String noteId, List<double> values) {}

  @override
  List<double>? getEmbedding(String noteId) => null;

  @override
  List<NoteEmbedding> listEmbeddings() => [];

  @override
  List<Note> listNeedingEmbedding({int limit = 25}) => [];

  @override
  void setDueAt(String noteId, DateTime? when) {}

  @override
  List<Note> listUpcomingReminders({int limit = 200}) => [];

  @override
  List<Note> listNeedingEnrichment({int limit = 50}) => [];
}

void main() {
  late _FakeNoteRepository fakeRepo;
  late NexToolRegistry registry;

  setUp(() {
    fakeRepo = _FakeNoteRepository();
    registry = NexToolRegistry(
      captureService: CaptureService(fakeRepo, deviceId: 'test-device'),
      tagService: TagService(fakeRepo),
      searchService: SearchService(fakeRepo),
    );
  });

  group('NexToolRegistry', () {
    test('registers exactly the Core-backed tools, all gated', () {
      final names = registry.definitions.map((d) => d.name).toSet();
      expect(names, {
        'create_note',
        'search_notes',
        'add_tag',
        'remove_tag',
        'list_tags',
      });
      for (final def in registry.definitions) {
        expect(def.requiresEntitlement, AiEntitlement.personalAssistant);
      }
    });

    test('does not register create_task or create_reminder', () {
      expect(registry.definitionFor('create_task'), isNull);
      expect(registry.definitionFor('create_reminder'), isNull);
    });
  });

  group('GatedToolExecutor', () {
    test('blocks a personalAssistant tool under free entitlement', () {
      final executor = GatedToolExecutor(
        registry,
        const StaticEntitlementProvider(AiEntitlement.free),
      );
      final result = executor.execute(
        const ToolCall(name: 'create_note', arguments: {'content': 'hi'}),
      );
      expect(result.success, isFalse);
      expect(fakeRepo._notes, isEmpty);
    });

    test('allows and dispatches under personalAssistant entitlement', () {
      final executor = GatedToolExecutor(
        registry,
        const StaticEntitlementProvider(AiEntitlement.personalAssistant),
      );
      final result = executor.execute(
        const ToolCall(
          name: 'create_note',
          arguments: {'content': 'remember this'},
        ),
      );
      expect(result.success, isTrue);
      expect(fakeRepo._notes, hasLength(1));
      expect(fakeRepo._notes.single.content, 'remember this');
    });

    test('reports unknown tool names as errors, not exceptions', () {
      final executor = GatedToolExecutor(
        registry,
        const StaticEntitlementProvider(AiEntitlement.personalAssistant),
      );
      final result = executor.execute(
        const ToolCall(name: 'delete_everything'),
      );
      expect(result.success, isFalse);
      expect(result.error, contains('unknown_tool'));
    });
  });
}
