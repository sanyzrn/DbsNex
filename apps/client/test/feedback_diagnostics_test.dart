import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/device_label.dart';
import 'package:nex_client/platform/feedback_service.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/widgets/feedback_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The diagnostics report can go with feedback, only when the person ticks
/// it, after seeing it (1.93.5).
void main() {
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await NexPreferences.load();
  });

  FeedbackService service(void Function(Map<String, dynamic> body) seen) =>
      FeedbackService(
        preferences: preferences,
        baseUrl: 'https://example.invalid',
        describeDevice: () async => NexDevice.label(release: '14'),
        client: MockClient((request) async {
          seen(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 202);
        }),
      );

  test('the report travels in the request only when given', () async {
    final bodies = <Map<String, dynamic>>[];
    final s = service(bodies.add);
    addTearDown(s.close);
    await s.send('one');
    await s.send('two', diagnostics: 'StateError at x');
    expect(bodies[0].containsKey('diagnostics'), isFalse);
    expect(bodies[1]['diagnostics'], 'StateError at x');
  });

  test('a message held for later keeps the report it was sent with', () {
    final raw = FeedbackService.encodePending(
      'hi',
      kind: FeedbackKind.bug,
      diagnostics: 'report',
    );
    final held = FeedbackService.decodePending(raw);
    expect(held.diagnostics, 'report');
    expect(FeedbackService.decodePending('plain old text').diagnostics, isNull);
  });

  Widget sheet(FeedbackService s, {String? report}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: FeedbackSheet(service: s, loadDiagnostics: () async => report),
    ),
  );

  testWidgets('the option appears only when there is a report, starts off, '
      'and shows the report before it is sent', (tester) async {
    final bodies = <Map<String, dynamic>>[];
    final s = service(bodies.add);
    addTearDown(s.close);

    await tester.pumpWidget(sheet(s));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('feedback-attach-diagnostics')),
      findsNothing,
    );

    // A fresh sheet: the report is read once, when the sheet opens.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(sheet(s, report: 'StateError in reminders'));
    await tester.pumpAndSettle();
    final option = find.byKey(const ValueKey('feedback-attach-diagnostics'));
    expect(option, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(option).value, isFalse);
    expect(find.text('StateError in reminders'), findsNothing);

    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(find.text('StateError in reminders'), findsOneWidget);
  });
}
