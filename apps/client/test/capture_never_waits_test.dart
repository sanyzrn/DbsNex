import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/db_worker.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;

/// Capture is the one thing in this app that is never allowed to wait.
///
/// The database worker handles one command at a time, chained onto a tail
/// future, and that is deliberate — it is what stops a capture running against
/// the database halfway through an import. But the AI commands were on that
/// same chain, and they do not wait on the database, they wait on a provider:
/// 90 seconds for text, three minutes for media. Every one of those seconds
/// was a second a capture behind them spent queued.
///
/// It was invisible from every angle. `scheduleEnrichment` says "never awaited
/// by capture UI", which was true of the caller and false of the queue
/// underneath it. The capture sheet's own comment named the hazard. And no
/// test could see it, because in a test suite no provider is ever actually
/// slow.
///
/// So this makes one slow on purpose. It is not a timing test — nothing here
/// measures milliseconds or depends on how fast the machine is. The provider
/// is held open until this test decides to release it, which makes the
/// question exact: with an AI call parked mid-flight, does a capture get
/// through, or does it sit behind it?
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_capture_wait_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<NexDbWorker> worker() async {
    final mediaDir = p.join(tmp.path, 'media');
    Directory(mediaDir).createSync(recursive: true);
    return NexDbWorker.spawn(
      dbPath: p.join(tmp.path, 'nex.sqlite'),
      deviceId: 'test',
      mediaDir: mediaDir,
      adapter: const _HangingAdapter(),
    );
  }

  test('a capture goes through while a provider call is still hanging', () async {
    final db = await worker();
    try {
      // Parked on `embed`, which never returns. On the old queue this held
      // the chain and everything behind it.
      var answered = false;
      unawaited(db.semanticSearch('anything').then((_) => answered = true));

      // The whole assertion: this resolves. Before the fix it could not,
      // because the command in front of it had not finished and never would.
      final note = await db.captureText('typed while the model was thinking');

      expect(note, isNotNull);
      expect(note!.content, 'typed while the model was thinking');
      // And it is really on disk, not merely acknowledged.
      expect((await db.getById(note.id))?.content, note.content);

      // A read gets through too — the timeline is not blocked either.
      expect(await db.timeline(limit: 10), isNotEmpty);

      // Still hanging, and this is what makes the assertions above mean
      // anything: it rules out the capture having got through simply because
      // the AI call returned early. Checked as "did it settle", not "was the
      // result empty" — an early `const []` is exactly the false pass an
      // emptiness check would have waved through.
      expect(
        answered,
        isFalse,
        reason: 'the provider call must still be in flight',
      );
    } finally {
      await db.close();
    }
  });

  test('a close does not hang behind a provider that never answers', () async {
    // The other half of taking these off the chain. Background work outlives
    // the queue, so shutdown has to be able to happen without it — otherwise
    // the fix for a blocked capture would be an app that cannot be closed.
    final db = await worker();
    unawaited(db.semanticSearch('anything'));

    await db.close().timeout(
      const Duration(seconds: 20),
      onTimeout: () => fail('close waited on a hanging provider call'),
    );
  });
}

/// A provider that is asked and never answers.
///
/// Const, because the adapter crosses an isolate boundary — see the note on
/// `_WorkerBoot.adapter`. A `Completer` held in a field would not survive the
/// trip; a future that simply never completes needs no state at all.
class _HangingAdapter implements AIAdapter {
  const _HangingAdapter();

  static Future<T> _never<T>() => Completer<T>().future;

  @override
  Future<Vector>? embed(String text) => _never();

  @override
  Future<Transcript>? transcribe(AudioRef audio) => _never();

  @override
  Future<OCRText>? ocr(ImageRef image) => _never();

  @override
  Future<Summary>? summarize(Note note) => _never();

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) => _never();
}
