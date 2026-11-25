import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/brief_refresh.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The cache that carried last night's greeting into the morning.
///
/// A phrase is stored with the day it was written for, the part of that day
/// and the interface language. Before 2.9.0 only the day and language were
/// stored, so at 09:00 the cache hit was a real hit — for a phrase written at
/// 23:00. These tests pin the missing half of the key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NexPreferences prefs;
  late NexBriefRefresh refresh;
  var calls = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await NexPreferences.load();
    calls = 0;
    refresh = NexBriefRefresh(prefs, clock: () => DateTime(2026, 3, 10, 9));
  });
  tearDown(() => prefs.dispose());

  Future<String?> ask({
    String part = 'morning',
    String dateKey = '2026-03-10',
    String? language = 'en',
    bool force = false,
    Future<String?> Function()? request,
  }) => refresh.headline(
    dateKey: dateKey,
    part: part,
    language: language,
    force: force,
    request:
        request ??
        () async {
          calls++;
          return 'Ready when you are';
        },
  );

  test('a phrase cached for tonight is not the morning greeting', () async {
    await prefs.setAiHeadline(
      text: 'Still up?',
      dateKey: '2026-03-10',
      lang: 'en',
      part: 'night',
    );
    final result = await ask(
      request: () async {
        calls++;
        return null;
      },
    );
    expect(result, isNull, reason: 'the local greeting holds the line');
    expect(calls, 1, reason: 'the new moment asks once');
  });

  test('a phrase cached for this moment is used without a request', () async {
    await prefs.setAiHeadline(
      text: 'Ready when you are',
      dateKey: '2026-03-10',
      lang: 'en',
      part: 'morning',
    );
    expect(await ask(), 'Ready when you are');
    expect(calls, 0);
  });

  test('a cache written without a part is not reused', () async {
    // Every install upgrading from 2.8.x has one of these.
    await prefs.setAiHeadline(
      text: 'Ready when you are',
      dateKey: '2026-03-10',
      lang: 'en',
    );
    expect(prefs.aiHeadlinePart, isNull);
    expect(await ask(), 'Ready when you are');
    expect(calls, 1);
    expect(prefs.aiHeadlinePart, 'morning');
  });

  test('the answer is stored with the part it was written for', () async {
    await ask(part: 'evening');
    expect(prefs.aiHeadlinePart, 'evening');
    expect(prefs.aiHeadlineDate, '2026-03-10');
    expect(prefs.aiHeadlineLang, 'en');
  });

  test('a flight for another part does not answer this one', () async {
    final night = Completer<String?>();
    final pending = ask(
      part: 'night',
      request: () {
        calls++;
        return night.future;
      },
    );
    expect(await ask(part: 'morning'), isNull);
    expect(calls, 1, reason: 'the night flight is not the morning answer');
    night.complete('Still up?');
    await pending;
    // And the night phrase went to the night cache, not into the morning.
    expect(prefs.aiHeadlinePart, 'night');
    expect(await ask(part: 'morning'), 'Ready when you are');
    expect(calls, 2);
  });

  test(
    'a failure at a new moment never returns the old moment phrase',
    () async {
      await prefs.setAiHeadline(
        text: 'Still up?',
        dateKey: '2026-03-10',
        lang: 'en',
        part: 'night',
      );
      expect(
        await ask(
          request: () async {
            calls++;
            throw StateError('offline');
          },
        ),
        isNull,
      );
    },
  );
}
