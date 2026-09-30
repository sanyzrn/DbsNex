import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/feedback_service.dart';
import 'package:nex_client/platform/metrics.dart';
import 'package:nex_client/screens/metrics_screen.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/widgets/feedback_sheet.dart';
import 'package:nex_client/widgets/nex_banner.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import 'support/nex_harness.dart';

/// W3.4: what Nex measures about itself — only when asked, only on the phone,
/// never the person's words.
void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_metrics_');
    file = File(p.join(tmp.path, 'metrics.json'));
  });

  tearDown(() {
    NexMetrics.shared = NexMetrics.off();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('the store', () {
    test('off records nothing and writes nothing', () {
      final metrics = NexMetrics(file)
        ..record(NexMetric.capture, const Duration(seconds: 1))
        ..beginSession()
        ..markCapture()
        ..flush();
      expect(metrics.stats(NexMetric.capture), isNull);
      expect(metrics.isEmpty, isTrue);
      expect(file.existsSync(), isFalse);
    });

    test('the usual and the slow end of recent samples', () {
      final metrics = NexMetrics(file, enabled: true);
      for (var ms = 100; ms <= 1000; ms += 100) {
        metrics.record(NexMetric.capture, Duration(milliseconds: ms));
      }
      final stats = metrics.stats(NexMetric.capture)!;
      expect(stats.count, 10);
      expect(stats.median, const Duration(milliseconds: 600));
      expect(stats.p90, const Duration(milliseconds: 1000));
    });

    test('keeps the newest ${NexMetrics.keep} samples only', () {
      final metrics = NexMetrics(file, enabled: true);
      for (var i = 0; i < NexMetrics.keep + 30; i++) {
        metrics.record(NexMetric.searchToOpen, Duration(milliseconds: i));
      }
      final stats = metrics.stats(NexMetric.searchToOpen)!;
      expect(stats.count, NexMetrics.keep);
      expect(stats.median.inMilliseconds, greaterThanOrEqualTo(30));
    });

    test('survives a restart, and switching off deletes it', () async {
      final metrics = NexMetrics(file, enabled: true)
        ..beginSession()
        ..record(NexMetric.launch, const Duration(milliseconds: 640))
        ..markCapture()
        ..flush();
      expect(file.existsSync(), isTrue);

      final again = NexMetrics(file);
      await again.setEnabled(true);
      expect(again.stats(NexMetric.launch)!.median.inMilliseconds, 640);
      expect(again.sessions.withCapture, 1);

      await again.setEnabled(false);
      expect(file.existsSync(), isFalse);
      expect(again.isEmpty, isTrue);
      await metrics.setEnabled(false);
    });

    test('a session with a capture and an error is not clean', () {
      final metrics = NexMetrics(file, enabled: true)
        ..beginSession()
        ..markCapture()
        ..markError();
      expect(metrics.sessions.withCapture, 1);
      expect(metrics.sessions.clean, 0);
      // An error is written at once: the process may not live to write it.
      final saved = jsonDecode(file.readAsStringSync()) as Map;
      expect((saved['sessions'] as List).single, [anything, true, true]);
    });

    test('the report is timings and counts, and says so', () {
      final metrics = NexMetrics(file, enabled: true)
        ..beginSession()
        ..record(NexMetric.capture, const Duration(milliseconds: 1800))
        ..markCapture();
      final report = metrics.report(platform: 'android');
      expect(report, contains('attached by choice'));
      expect(report, contains('Capture, open to saved: median 1.8 s'));
      expect(report, contains('Search to opening a note: no data'));
      expect(
        report,
        contains('Sessions with a capture: 1, without an error: 1'),
      );
    });
  });

  group('in the app', () {
    late NexTestHarness harness;

    setUp(() async {
      harness = await NexTestHarness.create(name: 'nex_metrics_app_');
      NexMetrics.shared = NexMetrics(file, enabled: true)..beginSession();
    });

    tearDown(() => harness.dispose());

    testWidgets('a capture is timed from the sheet opening to the note', (
      tester,
    ) async {
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      final state = tester.state<TimelineScreenState>(
        find.byType(TimelineScreen),
      );
      unawaited(state.openCapture());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'timed');
      await tester.pumpAndSettle();

      expect(NexMetrics.shared.stats(NexMetric.capture)?.count, 1);
      expect(NexMetrics.shared.sessions.withCapture, 1);
      Navigator.of(tester.element(find.byType(TextField).last)).pop();
      await tester.pumpAndSettle();
      NexMetrics.shared.flush();
    });

    testWidgets('a search is timed until the first note it opens', (
      tester,
    ) async {
      await harness.services.captureText('find the heating invoice');
      await harness.services.refreshTimeline();
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      final state = tester.state<TimelineScreenState>(
        find.byType(TimelineScreen),
      );
      unawaited(state.revealSearch());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'heating');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NoteCard).first);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(NexMetrics.shared.stats(NexMetric.searchToOpen)?.count, 1);
      NexMetrics.shared.flush();
    });
  });

  group('the screen', () {
    Widget app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

    testWidgets('off by default; on shows the numbers; off again deletes', (
      tester,
    ) async {
      final harness = await NexTestHarness.create(name: 'nex_metrics_ui_');
      addTearDown(harness.dispose);
      final metrics = NexMetrics(file);
      await tester.pumpWidget(
        app(MetricsScreen(preferences: harness.preferences, metrics: metrics)),
      );
      expect(harness.preferences.metricsEnabled, isFalse);
      expect(find.text('Capture, from opening to saved'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(harness.preferences.metricsEnabled, isTrue);
      expect(find.textContaining('Nothing measured yet'), findsOneWidget);

      metrics
        ..record(NexMetric.capture, const Duration(milliseconds: 1500))
        ..markCapture();
      await tester.pumpWidget(
        app(
          MetricsScreen(
            key: const ValueKey('again'),
            preferences: harness.preferences,
            metrics: metrics,
          ),
        ),
      );
      expect(find.text('Capture, from opening to saved'), findsOneWidget);
      expect(find.textContaining('Usually 1.5 s'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(harness.preferences.metricsEnabled, isFalse);
      expect(metrics.isEmpty, isTrue);
    });

    testWidgets('feedback attaches the measurements only when ticked', (
      tester,
    ) async {
      final harness = await NexTestHarness.create(name: 'nex_metrics_fb_');
      addTearDown(harness.dispose);
      final metrics = NexMetrics(file, enabled: true)
        ..record(NexMetric.capture, const Duration(milliseconds: 900));
      final sent = <String>[];
      final service = FeedbackService(
        preferences: harness.preferences,
        baseUrl: 'https://example.invalid',
        client: MockClient((request) async {
          sent.add(
            (jsonDecode(request.body) as Map<String, dynamic>)['message']
                as String,
          );
          return http.Response('{}', 202);
        }),
      );
      addTearDown(service.close);

      NexMetrics.shared = metrics;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => FeedbackSheet.show(context, service: service),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      Future<void> send(String text, {required bool attach}) async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, text);
        if (attach) {
          await tester.tap(find.byType(Checkbox));
          await tester.pump();
          expect(find.textContaining('attached by choice'), findsOneWidget);
        }
        final button = find.byType(FilledButton);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        nexHideBanner();
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      await send('plain', attach: false);
      await send('with numbers', attach: true);

      expect(sent.first, 'plain');
      expect(sent.last, startsWith('with numbers\n\nNex measurements'));
      expect(sent.last, contains('Capture, open to saved: median 900 ms'));
    });
  });
}
