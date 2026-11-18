import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/crash_reporter.dart';

/// The fast path in the diagnostics note writer: a new line unlike any old
/// one lands as one small append, and only a line that collapses into an
/// earlier one (the counted repeat) or crosses a bound pays for the full
/// rewrite. The file has to come out exactly as the rewrite semantics would
/// have written it — the earlier suite in `crash_reporter_test.dart` holds
/// the rest of that contract; these add the parts only the append path can
/// show. (A file of its own because the sibling test file carries a NUL byte
/// in its source, which makes any patch touching it binary.)
void main() {
  late Directory tmp;
  late File logFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_crash_fast_');
    logFile = File('${tmp.path}/crash_log.txt');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('distinct notes append without rewriting the earlier ones', () async {
    final log = NexCrashLog(logFile);
    await log.note('first entry');
    for (var i = 0; i < 30; i++) {
      await log.note('distinct entry $i');
    }
    await log.note('Bearer sk-secret at https://secret.example/x');
    await log.flush();
    final contents = logFile.readAsStringSync();
    for (var i = 0; i < 30; i++) {
      expect(contents, contains('distinct entry $i'));
    }
    // The appended entry is redacted on its way in, exactly as the rewrite
    // path always redacted it.
    expect(contents, isNot(contains('sk-secret')));
    expect(contents, isNot(contains('secret.example')));
    // No separator was doubled or dropped on the way. (The separator is a
    // record separator between newlines, written here as code rather than a
    // literal so the file itself stays plain text.)
    final separator = '\n${String.fromCharCode(0x1e)}\n';
    expect(contents, isNot(contains(separator + separator)));
    expect(contents.startsWith('\n'), isFalse);
    expect(
      contents.endsWith('\n'),
      isFalse,
      reason: 'an entry never ends with a stray separator tail',
    );
  });

  test(
    'a note that repeats one from a previous session still counts it',
    () async {
      // A fresh logger in a fresh process (an empty in-memory cache) has to
      // read the earlier line on disk to collapse into it.
      await NexCrashLog(logFile).note('recurring line');
      await NexCrashLog(logFile).flush();
      final second = NexCrashLog(logFile);
      await second.note('recurring line');
      await second.flush();
      final contents = logFile.readAsStringSync();
      expect('recurring line'.allMatches(contents), hasLength(1));
      expect(contents, contains('×2 since'));
    },
  );

  test('an appended note is found by the shareable report', () async {
    final log = NexCrashLog(logFile);
    await log.note('the first line is read from disk to build the cache');
    await log.flush();
    await log.note('an appended line rides along');
    await log.flush();
    final report = log.shareable()!;
    expect(report, contains('an appended line rides along'));
    expect(report, contains('the first line'));
  });
}
