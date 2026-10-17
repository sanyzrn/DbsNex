import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';

import 'package:nex_client/platform/nex_services.dart';

import 'support/nex_harness.dart';

class _Local implements ChatAdapter {
  final calls = <List<ChatMessage>>[];
  Completer<ChatResponse>? held;
  @override
  bool get available => true;
  @override
  Future<void>? warmUp() => null;
  @override
  Future<void>? release() => null;
  @override
  Future<ChatResponse>? sendMessage(List<ChatMessage> history) {
    calls.add(history);
    return held?.future ??
        Future.value(
          ChatResponse(
            content: history.first.content.contains('label notes')
                ? 'Ideas, Plans'
                : 'A model-generated summary.',
          ),
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(ChatAdapterBinding.reset);

  test(
    'manual summary and tags use downloaded model; capture does not',
    () async {
      final h = await NexTestHarness.create(preferences: {'ai.enabled': true});
      addTearDown(h.dispose);
      final local = _Local();
      ChatAdapterBinding.bind(local);
      final note = (await h.services.captureText(
        'A detailed source note with several ideas and plans. '
        'It must remain intact while a shorter model-generated summary is stored separately.',
      ))!;
      expect(local.calls, isEmpty);
      final summary = await h.services.summarizeOnDemand(note.id);
      expect(summary?.text, 'A model-generated summary.');
      expect((await h.services.getById(note.id))?.summaryText, summary?.text);
      expect((await h.services.getById(note.id))?.content, note.content);
      expect((await h.services.suggestTags(note.id)).map((t) => t.name), [
        'Ideas',
        'Plans',
      ]);
      expect(local.calls, hasLength(2));
      await h.preferences.setAiEnabled(false);
      await h.services.summarizeOnDemand(note.id);
      expect(local.calls, hasLength(2));
    },
  );

  test('late local summary cannot overwrite an edited note', () async {
    final h = await NexTestHarness.create(preferences: {'ai.enabled': true});
    addTearDown(h.dispose);
    final local = _Local()..held = Completer<ChatResponse>();
    ChatAdapterBinding.bind(local);
    final note = (await h.services.captureText(
      'Original source text long enough to be summarized by the model.',
    ))!;
    final pending = h.services.summarizeOnDemand(note.id);
    while (local.calls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await h.services.updateNote(
      note.id,
      'The source changed while inference was running.',
    );
    local.held!.complete(const ChatResponse(content: 'Old summary.'));
    expect(await pending, isNull);
    expect(
      (await h.services.getById(note.id))?.summaryText,
      isNot('Old summary.'),
    );
  });
}
