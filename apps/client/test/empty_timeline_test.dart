import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/empty_timeline.dart';

void main() {
  testWidgets('first launch teaches the promise without a tour', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: EmptyTimeline()),
      ),
    );
    expect(find.text('Anything you put here is kept.'), findsOneWidget);
    expect(find.text('There is no Save button.'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });
}
