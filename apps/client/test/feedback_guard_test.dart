import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/feedback_service.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/widgets/feedback_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A typed complaint used to be one pull of the sheet away from gone — the
/// sheet closed over it on any drag, any tap outside, any Back. The words
/// are guarded now, the way an editor's are.
void main() {
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await NexPreferences.load();
  });

  FeedbackService service() => FeedbackService(
    preferences: preferences,
    baseUrl: 'https://example.invalid',
    client: MockClient((_) async => http.Response('{}', 202)),
  );

  Widget host() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => FeedbackSheet.show(context, service: service()),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  testWidgets('an empty sheet closes on Back without asking', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FeedbackSheet), findsNothing);
  });

  testWidgets('typed words ask before Back closes over them', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'the sync stalls on large libraries',
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // Still up, and asking — the words are the sheet's unsaved work.
    expect(find.byType(FeedbackSheet), findsOneWidget);
    expect(find.text('Discard unsaved changes?'), findsOneWidget);

    // Keep editing: the words stay.
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(FeedbackSheet), findsOneWidget);
    expect(find.text('the sync stalls on large libraries'), findsOneWidget);
  });

  testWidgets('discard, said twice, is honoured and the sheet goes', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'a complaint');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(FeedbackSheet), findsNothing);
  });
}
