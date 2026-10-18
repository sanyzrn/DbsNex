import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/brief_refresh.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NexPreferences prefs;
  late NexBriefRefresh refresh;
  late DateTime now;
  var calls = 0;
  Future<String?> answer() async {
    calls++;
    return 'new brief';
  }

  Future<NexBriefRefreshResult> ask({
    String source = 'new',
    bool force = false,
    Future<String?> Function()? request,
  }) => refresh.refresh(
    fingerprint: source,
    dateKey: '2026-10-18',
    force: force,
    request: request ?? answer,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await NexPreferences.load();
    now = DateTime.utc(2026, 10, 18, 12);
    calls = 0;
    refresh = NexBriefRefresh(prefs, clock: () => now);
  });
  tearDown(() => prefs.dispose());

  test(
    'automatic needs changed information AND a full hour since success',
    () async {
      await ask();
      expect(calls, 1);
      now = now.add(const Duration(minutes: 59, seconds: 59));
      await ask(source: 'changed');
      expect(calls, 1);
      now = now.add(const Duration(seconds: 1));
      await ask(source: 'changed');
      expect(calls, 2);
      now = now.add(const Duration(days: 5));
      await ask(source: 'changed');
      expect(calls, 2);
    },
  );

  test(
    'a failure preserves success and retries only after fifteen minutes, across reload',
    () async {
      await ask();
      final success = prefs.aiDaySummaryAt;
      now = now.add(const Duration(hours: 1));
      final failed = await ask(
        source: 'changed',
        request: () async {
          calls++;
          throw StateError('offline');
        },
      );
      expect(failed.failed, isTrue);
      expect(failed.text, 'new brief');
      expect(prefs.aiDaySummaryAt, success);
      expect(prefs.aiDaySummarySource, 'new');
      final reloaded = await NexPreferences.load();
      addTearDown(reloaded.dispose);
      refresh = NexBriefRefresh(reloaded, clock: () => now);
      now = now.add(const Duration(minutes: 14, seconds: 59));
      await ask(source: 'changed again');
      expect(calls, 2);
      now = now.add(const Duration(seconds: 1));
      await ask(source: 'changed again');
      expect(calls, 3);
      expect(reloaded.aiDaySummaryFailedAt, isNull);
    },
  );

  test('empty answers do not stamp a successful generation', () async {
    await ask(request: () async => '   ');
    expect(prefs.aiDaySummaryAt, isNull);
    expect(prefs.aiDaySummaryText, isNull);
    expect(prefs.aiDaySummaryFailedAt!.isAtSameMomentAs(now), isTrue);
    await ask();
    expect(calls, 0);
    now = now.add(const Duration(minutes: 15));
    await ask();
    expect(calls, 1);
  });

  test('manual refresh bypasses both cooldowns and unchanged source', () async {
    await ask();
    await ask(force: true);
    await ask(force: true, request: () async => null);
    expect(prefs.aiDaySummaryFailedAt!.isAtSameMomentAs(now), isTrue);
    await ask(force: true);
    expect(calls, 3);
    expect(prefs.aiDaySummaryFailedAt, isNull);
  });

  test(
    'concurrent automatic/manual calls share one flight through cache persistence',
    () async {
      final reply = Completer<String?>();
      final first = ask(
        request: () {
          calls++;
          return reply.future;
        },
      );
      final second = ask(force: true);
      expect(identical(first, second), isTrue);
      expect(calls, 1);
      reply.complete('saved before flight completes');
      await Future.wait([first, second]);
      expect(prefs.aiDaySummaryText, 'saved before flight completes');
      await ask();
      expect(calls, 1);
    },
  );

  test(
    'changing output language preserves readable cache and success time',
    () async {
      await ask();
      final before = prefs.aiDaySummaryAt;
      await prefs.setAiOutputLanguage(AiOutputLanguage.persian);
      expect(prefs.aiDaySummaryText, 'new brief');
      expect(prefs.aiDaySummaryAt, before);
      await ask(source: 'different language');
      expect(calls, 1);
      await ask(source: 'different language', force: true);
      expect(calls, 2);
    },
  );

  test('clock rollback respects both cooldowns', () async {
    await ask();
    now = now.subtract(const Duration(hours: 2));
    await ask(source: 'changed');
    expect(calls, 1);
    await ask(force: true, request: () async => null);
    now = now.subtract(const Duration(hours: 1));
    await ask(source: 'changed');
    expect(calls, 1);
  });

  test('headline requests coalesce and failures survive reopening', () async {
    final reply = Completer<String?>();
    Future<String?> headline({bool force = false}) => refresh.headline(
      dateKey: 'today',
      language: 'fa',
      force: force,
      request: () {
        calls++;
        return reply.future;
      },
    );
    final first = headline();
    final second = headline(force: true);
    expect(identical(first, second), isTrue);
    reply.complete(null);
    await first;
    refresh = NexBriefRefresh(prefs, clock: () => now);
    await headline();
    expect(calls, 1);
    now = now.add(const Duration(minutes: 15));
    await headline();
    expect(calls, 2);
    await headline(force: true);
    expect(calls, 3);
  });
}
