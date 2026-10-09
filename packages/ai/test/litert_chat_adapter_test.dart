import 'dart:async';
import 'dart:io';

import 'package:flutter_litert_lm/flutter_litert_lm.dart' show LiteLmEngine;
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/nex_ai.dart';

/// What can be proved without a phone.
///
/// The inference itself cannot be: LiteRT-LM is a platform plugin behind a
/// method channel, and the weights are 2.6 GB. What *is* worth pinning down is
/// the behaviour around it — the part that decides whether the app asks the
/// model anything at all, and the part that decides how much of a conversation
/// gets re-processed. Both are ours, and both are where a mistake is silent.
void main() {
  group('availability is a state, not an error', () {
    test(
      'a model that is not downloaded yet answers null, before awaiting',
      () {
        final adapter = LiteRtChatAdapter(
          modelPath: '/does/not/exist/gemma-4-e2b.litertlm',
        );

        // Null rather than a thrown or a failed Future: every AIAdapter method
        // follows this convention, and callers check before they await.
        expect(
          adapter.sendMessage(const [
            ChatMessage(role: ChatRole.user, content: 'hello'),
          ]),
          isNull,
        );
        expect(adapter.available, isFalse);
      },
    );

    test('an empty path is unavailable rather than a filesystem question', () {
      expect(LiteRtChatAdapter(modelPath: '').available, isFalse);
    });

    test('a following adapter asks again which model, every time', () {
      // The on-device screen can switch models; the bound adapter must not
      // keep answering for the one it started with.
      var path = '';
      final adapter = LiteRtChatAdapter.following(() => path);
      expect(adapter.modelPath, '');
      path = '/models/minicpm5-2b-int4/MiniCPM5-2B_int4.litertlm';
      expect(adapter.modelPath, path);
      expect(adapter.available, isFalse);
    });

    test('the instructions open the first user turn, once', () {
      const turns = [
        ChatMessage(role: ChatRole.user, content: 'what is left to do?'),
        ChatMessage(role: ChatRole.assistant, content: 'The plumber.'),
        ChatMessage(role: ChatRole.user, content: 'and tomorrow?'),
      ];
      final prepared = LiteRtChatAdapter.withInstructions(
        'You are the assistant inside Nex.',
        turns,
      );
      expect(prepared, hasLength(3));
      expect(prepared.first.content, startsWith('[Instructions from the Nex'));
      expect(prepared.first.content, contains('You are the assistant inside'));
      expect(prepared.first.content, endsWith('what is left to do?'));
      // Only the first: later turns are the user's words alone.
      expect(prepared[1].content, 'The plumber.');
      expect(prepared[2].content, 'and tomorrow?');
      // Nothing to add, nothing added.
      expect(LiteRtChatAdapter.withInstructions(null, turns), same(turns));
    });

    test('an empty history is never sent anywhere', () {
      final adapter = LiteRtChatAdapter(modelPath: '');
      expect(adapter.sendMessage(const []), isNull);
    });
  });

  group('the scope ceiling is applied by the adapter, not by its callers', () {
    test('withScopeCeiling prepends exactly one system message', () {
      final once = withScopeCeiling(const [
        ChatMessage(role: ChatRole.user, content: 'hi'),
      ]);
      expect(once.first.role, ChatRole.system);
      expect(once.first.content, nexChatScopeCeilingPrompt);

      // Applying it again must not stack a second one — the adapter calls this
      // on every message, so a non-idempotent version would grow the prompt
      // by the whole ceiling on every turn of a conversation.
      final twice = withScopeCeiling(once);
      expect(
        twice.where((ChatMessage m) => m.role == ChatRole.system),
        hasLength(1),
      );
    });
  });

  test(
    'the placeholder it replaces still answers, and says it is one',
    () async {
      // Kept bound until model management exists, so the "ai" flavor is never
      // left with nothing behind ChatAdapterBinding.
      final reply = await const PlaceholderLocalChatAdapter().sendMessage(
        const [ChatMessage(role: ChatRole.user, content: 'hello')],
      )!;
      expect(reply.content, contains('Phase 1'));
    },
  );

  test('release is a no-op while no model is loaded', () {
    // Called from the app's lifecycle on every pause; with nothing loaded
    // there is nothing to wait for and nothing to close (PERF-02).
    expect(LiteRtChatAdapter(modelPath: '').release(), isNull);
  });

  group('loading the model', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nex_litert_');
      path = '${dir.path}/model.litertlm';
      File(path).writeAsStringSync('weights');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    File marker() => File('$path.loading');

    test('two callers at once share one load, never two', () async {
      // Opening the assistant warms the model up; a message sent in the
      // same moment used to start a second load, and two copies of the
      // weights do not fit on a phone.
      var loads = 0;
      final release = Completer<void>();
      final adapter = LiteRtChatAdapter(
        modelPath: path,
        preferGpu: false,
        loadEngine: (config) async {
          loads++;
          await release.future;
          return _FakeEngine();
        },
      );

      final first = adapter.ensureEngine();
      final second = adapter.ensureEngine();
      release.complete();
      expect(identical(await first, await second), isTrue);
      expect(loads, 1);
    });

    test('a load that never came back once is tried again', () async {
      // Swiped away, or reclaimed by Android mid-load: not a broken
      // backend. One of these used to bar the backend for good.
      marker().writeAsStringSync('cpu');
      var loads = 0;
      final adapter = LiteRtChatAdapter(
        modelPath: path,
        preferGpu: false,
        loadEngine: (config) async {
          loads++;
          return _FakeEngine();
        },
      );

      await adapter.ensureEngine();
      expect(loads, 1);
      expect(marker().existsSync(), isFalse, reason: 'cleared on success');
    });

    test('twice in a row, recently, and the backend is skipped', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      marker().writeAsStringSync('cpu 2 $now');
      final adapter = LiteRtChatAdapter(
        modelPath: path,
        preferGpu: false,
        loadEngine: (config) async => _FakeEngine(),
      );

      await expectLater(adapter.ensureEngine(), throwsStateError);
    });

    test('a skipped backend is tried again once the strikes expire', () async {
      final old = DateTime.now()
          .subtract(LiteRtChatAdapter.strikeExpiry + const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      marker().writeAsStringSync('cpu 2 $old');
      var loads = 0;
      final adapter = LiteRtChatAdapter(
        modelPath: path,
        preferGpu: false,
        loadEngine: (config) async {
          loads++;
          return _FakeEngine();
        },
      );

      await adapter.ensureEngine();
      expect(loads, 1);
    });

    test('the attempt is on disk while the load is running', () async {
      // What survives a crash: written before the native call, gone after.
      final release = Completer<void>();
      String? during;
      final adapter = LiteRtChatAdapter(
        modelPath: path,
        preferGpu: false,
        loadEngine: (config) async {
          during = marker().readAsStringSync();
          await release.future;
          return _FakeEngine();
        },
      );

      final loading = adapter.ensureEngine();
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await loading;
      expect(during, startsWith('cpu 1 '));
      expect(marker().existsSync(), isFalse);
    });

    test('a load that fails politely clears its attempt', () async {
      final adapter = LiteRtChatAdapter(
        modelPath: path,
        preferGpu: false,
        loadEngine: (config) async => throw StateError('no OpenCL'),
      );

      await expectLater(adapter.ensureEngine(), throwsStateError);
      expect(marker().existsSync(), isFalse);
    });
  });
}

class _FakeEngine implements LiteLmEngine {
  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
