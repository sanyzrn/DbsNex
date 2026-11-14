import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/nex_services.dart';

import 'support/nex_harness.dart';

/// The brief against the timeline's window, and the pull against the brief's
/// flights. Both are contracts about *reach*: what the brief is allowed to
/// see, and what a gesture is allowed to expect.
void main() {
  testWidgets('a reminder beyond the timeline window still reaches the brief', (
    tester,
  ) async {
    final h = await NexTestHarness.create(name: 'nex_brief_window_');
    addTearDown(h.dispose);
    await h.preferences.setSponsorAttemptedAt(DateTime.now());
    await h.preferences.setBriefStyle(NexBriefStyle.report);
    await h.preferences.setBriefLength(NexBriefLength.medium);
    await h.preferences.setShowGreeting(false);

    // One more note than the timeline's base window, so the two oldest
    // sit below the cut: 200 newer notes stand in front of them.
    const window = 200;
    var oldest = '';
    var second = '';
    for (var i = 0; i < window + 5; i++) {
      final note = await h.services.captureText('filler note number $i');
      if (i == 0) oldest = note!.id;
      if (i == 1) second = note!.id;
    }
    await h.db.setDueAt(oldest, DateTime.now().add(const Duration(days: 1)));
    await h.db.setUrgent(second, true);

    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('timeline-recap'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('filler note number 0'),
      ),
      findsOneWidget,
      reason: 'the reminder set beyond the window is due tomorrow',
    );
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('filler note number 1'),
      ),
      findsOneWidget,
      reason: 'an urgent note beyond the window outranks filler',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a pull shares the flight in progress and still forces a fresh one after',
    (tester) async {
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = null;
      final requests = <Map<String, dynamic>>[];
      final gates = <Completer<void>>[];
      late HttpServer server;
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          requests.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '📝 the brief number ${requests.length}',
                  },
                  'finish_reason': 'stop',
                },
              ],
            }),
          );
          await request.response.close();
        });
      });
      addTearDown(() async {
        HttpOverrides.global = previousHttp;
        for (final gate in gates) {
          if (!gate.isCompleted) gate.complete();
        }
        await server.close(force: true);
      });

      final h = await NexTestHarness.create(name: 'nex_brief_pull_');
      addTearDown(h.dispose);
      await h.preferences.setSponsorAttemptedAt(DateTime.now());
      await h.preferences.setAiEnabled(true);
      await h.preferences.setAiProvider(
        AiProviderConfig(
          provider: AiProvider.custom,
          apiKey: 'fixture',
          model: 'fixture',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
        ),
      );
      await h.preferences.setShowGreeting(false);
      await h.services.captureText('something to summarise');

      await tester.pumpWidget(h.app());
      // The cold start asks on its own: no cache, a library with a note.
      await _until(
        tester,
        () => requests.length == 1,
        'the automatic brief request',
      );

      // A pull while that request is still held joins it. It must not start a
      // second one: the flight in progress is the refresh the pull waits for.
      await _pullDown(tester);
      await tester.runAsync(() async {
        gates.first.complete();
      });
      await _until(
        tester,
        () => h.preferences.lastRecap?.contains('the brief number 1') == true,
        'the joined flight to land',
      );
      expect(requests, hasLength(1));
      await tester.pumpAndSettle();

      // Nothing has changed and the hour is nowhere near up. A pull is a
      // gesture, not a delivery: it asks anyway.
      await _pullDown(tester);
      await _until(
        tester,
        () => requests.length == 2,
        'the pulled brief request',
      );
      await tester.runAsync(() async {
        gates[1].complete();
      });
      await _until(
        tester,
        () => h.preferences.lastRecap?.contains('the brief number 2') == true,
        'the pulled flight to land',
      );
      expect(requests, hasLength(2));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the headline reads capped excerpts, not whole notes', (
    tester,
  ) async {
    final previousHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    final requests = <Map<String, dynamic>>[];
    var served = 0;
    late HttpServer server;
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Good morning'},
                'finish_reason': 'stop',
              },
            ],
          }),
        );
        await request.response.close();
        served++;
      });
    });
    addTearDown(() async {
      HttpOverrides.global = previousHttp;
      await server.close(force: true);
    });

    final h = await NexTestHarness.create(name: 'nex_brief_headline_');
    addTearDown(h.dispose);
    await h.preferences.setSponsorAttemptedAt(DateTime.now());
    await h.preferences.setAiEnabled(true);
    await h.preferences.setAiProvider(
      AiProviderConfig(
        provider: AiProvider.custom,
        apiKey: 'fixture',
        model: 'fixture',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
      ),
    );
    await h.preferences.setShowGreeting(true);
    await h.preferences.setShowDaySummary(false);
    await h.services.captureText('renew the domain before it lapses ' * 300);

    await tester.pumpWidget(h.app());
    await _until(tester, () => requests.isNotEmpty, 'the greeting request');

    String systemOf(Map<String, dynamic> request) =>
        (request['messages'] as List).first['content'] as String;
    String userOf(Map<String, dynamic> request) =>
        (request['messages'] as List).last['content'] as String;
    final headline = requests.firstWhere(
      (request) => systemOf(request).contains('greeting a notes app'),
    );
    final sent = userOf(headline);
    expect(sent, contains('renew the domain'));
    // A mood line: one capped excerpt per note, not the note itself. The
    // full text is more than five thousand characters; the whole message,
    // time of day included, is a fraction of that.
    expect(sent.length, lessThan(600));
    // The reply is real I/O outside the fake clock: wait until it has landed
    // on screen before the tree goes away. Ending at the request left the
    // adapter's 20-second timeout pending whenever the reply was slower than
    // the asserts — a failure under load, not a flake.
    await _until(
      tester,
      () => find.textContaining('Good morning').evaluate().isNotEmpty,
      'the greeting reply on screen',
    );
    // And every request the server took has had its answer — a second one
    // can start after the first under load. A short real-time pause lets a
    // late one begin before the count is trusted.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await _until(
      tester,
      () => served == requests.length,
      'every request answered',
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}

/// Pumps short frames while a real-async condition outside the fake clock
/// (a local HTTP server) comes true.
Future<void> _until(
  WidgetTester tester,
  bool Function() condition,
  String what,
) async {
  // Up to ten seconds of real time: two (100 × 20ms) ran out under the full
  // suite's parallel load, with the local server's reply still on its way.
  for (var i = 0; i < 500 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: 'timed out waiting for $what');
}

/// The pull-to-refresh gesture, as a finger performs it.
Future<void> _pullDown(WidgetTester tester) async {
  final list = find.byType(CustomScrollView).first;
  final top = tester.getTopLeft(list) + const Offset(200, 160);
  final gesture = await tester.startGesture(top);
  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(top + Offset(0, i * 25.0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 100));
}
