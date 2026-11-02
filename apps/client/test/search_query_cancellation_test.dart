import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/note_search.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_core/nex_core.dart';
import 'support/nex_harness.dart';

class _Queries extends NullAIAdapter implements QueryEmbeddingAdapter {
  final queries = <String>[];
  Completer<Vector>? pending;
  var cancelled = 0;

  @override
  Future<Vector> embed(String text) async => const Vector([1, 0]);
  @override
  Future<Vector> embedQuery(String text) {
    queries.add(text);
    return (pending = Completer<Vector>()).future;
  }

  @override
  void cancelQueryEmbedding() {
    if (pending case final call? when !call.isCompleted) {
      cancelled++;
      call.completeError(StateError('cancelled query'));
    }
  }
}

void main() {
  test(
    'keywords appear before embeddings; typing cancels only the old query',
    () async {
      final adapter = _Queries();
      final h = await NexTestHarness.create(adapter: adapter);
      addTearDown(h.dispose);
      await h.db.setAiCapabilities(const AiCapabilities(semanticSearch: true));
      final note = await h.services.captureText('keyword first');
      await h.db.enrichNote(note!.id);
      final search = NoteSearchController(services: h.services);
      addTearDown(search.dispose);
      search.query.text = 'keyword';
      final first = search.run();
      for (var i = 0; i < 20 && adapter.queries.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(search.results.map((n) => n.id), [note.id]);
      expect(adapter.queries, ['keyword']);
      search.query.text = 'xy';
      search.schedule();
      await first;
      await search.run();
      expect(adapter.cancelled, 1);
      expect(adapter.queries, [
        'keyword',
      ], reason: 'short queries use only local search');
      expect(
        search.results,
        isEmpty,
        reason: 'old keyword results do not survive a new query',
      );
    },
  );

  testWidgets('typing pauses start one semantic request for the final query', (
    tester,
  ) async {
    final adapter = _Queries();
    final h = await NexTestHarness.create(adapter: adapter);
    addTearDown(h.dispose);
    await h.db.setAiCapabilities(const AiCapabilities(semanticSearch: true));
    final search = NoteSearchController(services: h.services);
    addTearDown(search.dispose);
    search.query.text = 'kit';
    search.schedule();
    await tester.pump(const Duration(milliseconds: 200));
    search.query.text = 'kitchen';
    search.schedule();
    await tester.pump(const Duration(milliseconds: 150));
    expect(adapter.queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    expect(adapter.queries, ['kitchen']);
    adapter.pending!.complete(const Vector([1, 0]));
    await tester.pump();
  });
}
