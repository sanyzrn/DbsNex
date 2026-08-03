import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/note_search.dart';

import 'support/in_process_db.dart';

/// Two fixed directions rather than real embeddings: cosine similarity only
/// cares about angle, so "soup" and "dinner" landing on the same axis is
/// enough to prove the search path without a real model.
const _mealAxis = Vector([1, 0]);
const _budgetAxis = Vector([0, 1]);

class _FakeEmbedAdapter implements AIAdapter {
  const _FakeEmbedAdapter();

  @override
  Future<Vector>? embed(String text) async {
    final lower = text.toLowerCase();
    if (lower.contains('soup') ||
        lower.contains('recipe') ||
        lower.contains('dinner')) {
      return _mealAxis;
    }
    if (lower.contains('budget') ||
        lower.contains('invoice') ||
        lower.contains('quarter')) {
      return _budgetAxis;
    }
    return const Vector([0.5, 0.5]);
  }

  @override
  Future<Transcript>? transcribe(AudioRef audio) => null;

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) => null;

  @override
  Future<Summary>? summarize(Note note) => null;

  @override
  Future<OCRText>? ocr(ImageRef image) => null;
}

void main() {
  late Directory tmp;
  late NexServices services;

  Future<NexServices> build() async {
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    return NexServices.forTest(
      worker: InProcessDb(
        dbPath: dbPath,
        deviceId: 'test',
        adapter: const _FakeEmbedAdapter(),
      ),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_semantic_search_');
    services = await build();
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'a query with no keyword overlap still finds the note about the same thing',
    () async {
      await services.worker.setAiCapabilities(
        const AiCapabilities(semanticSearch: true),
      );
      final meal = await services.captureText(
        "My grandmother's soup recipe for winter",
      );
      final budget = await services.captureText('Quarterly budget review');
      await services.worker.enrichNote(meal!.id);
      await services.worker.enrichNote(budget!.id);

      final search = NoteSearchController(services: services);
      search.query.text = 'dinner';
      await search.run();

      // Nothing in either note shares the word "dinner" — a keyword index
      // finds nothing at all.
      expect(search.results, isEmpty);
      // But the soup note sits on the same meaning-axis as "dinner"; the
      // budget note does not.
      expect(search.semanticResults.map((n) => n.id), [meal.id]);
    },
  );

  test(
    'turning the capability off leaves no meaning-based fallback at all',
    () async {
      await services.worker.setAiCapabilities(
        const AiCapabilities(semanticSearch: false),
      );
      final meal = await services.captureText(
        "My grandmother's soup recipe for winter",
      );
      await services.worker.enrichNote(meal!.id);

      final search = NoteSearchController(services: services);
      search.query.text = 'dinner';
      await search.run();

      expect(search.results, isEmpty);
      expect(search.semanticResults, isEmpty);
    },
  );

  test(
    'clear() drops any semantic results left over from the last search',
    () async {
      await services.worker.setAiCapabilities(
        const AiCapabilities(semanticSearch: true),
      );
      final meal = await services.captureText(
        "My grandmother's soup recipe for winter",
      );
      await services.worker.enrichNote(meal!.id);

      final search = NoteSearchController(services: services);
      search.query.text = 'dinner';
      await search.run();
      expect(search.semanticResults, isNotEmpty);

      search.clear();

      expect(search.semanticResults, isEmpty);
    },
  );
}
