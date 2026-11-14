import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/db_worker.dart';
import 'package:path/path.dart' as p;

/// [NexDbWorker.close] must finish even when the worker cannot answer.
///
/// The close reply comes after the worker's serial chain drains, and the
/// chain serves one command at a time. A command stuck on I/O that will
/// never return — here, an import whose file is a FIFO with no writer, so
/// the worker's open blocks in the kernel — used to make `close()` wait
/// forever, and everything that waits on close with it: the session
/// teardown, and the restart a restore asks for. Close is bounded now; the
/// isolate is taken down regardless, which is what release always was.
///
/// A real spawn, not the in-process fake, because the whole point is one
/// isolate blocked in native code while another decides to stop waiting.
void main() {
  if (!Platform.isLinux) return; // FIFOs are the mechanism; skip elsewhere.

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_db_close_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('close finishes while the worker is stuck on a chain command', () async {
    final fifo = p.join(tmp.path, 'stuck.zip');
    final made = await Process.run('mkfifo', [fifo]);
    expect(made.exitCode, 0, reason: 'mkfifo is how the worker gets stuck');

    final worker = await NexDbWorker.spawn(
      dbPath: p.join(tmp.path, 'nex.sqlite'),
      deviceId: 'test',
      mediaDir: tmp.path,
    );

    // The import parks the worker's chain on an open() that cannot return.
    // Never awaited: its answer is not the point, and none is coming.
    // ignore: unawaited_futures
    worker.importNotes(fifo, mediaDir: tmp.path);

    const grace = Duration(milliseconds: 250);
    final previousGrace = NexDbWorker.closeGrace;
    NexDbWorker.closeGrace = grace;
    addTearDown(() => NexDbWorker.closeGrace = previousGrace);

    final started = Stopwatch()..start();
    await worker.close();
    expect(
      started.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: 'close must not wait on a worker that cannot say goodbye',
    );
    expect(NexDbWorker.debugLiveIsolates, 0);

    // Let the blocked open return (a writer arriving, then EOF) so the
    // killed isolate can finish going away rather than pinning a thread.
    final writer = File(fifo).openSync(mode: FileMode.write);
    await writer.close();
  });
}
