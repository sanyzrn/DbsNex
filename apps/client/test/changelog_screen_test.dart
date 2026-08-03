import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/app_update.dart';
import 'package:nex_client/screens/changelog_screen.dart';

Future<void> _pump(WidgetTester tester, UpdateChecker checker) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangelogScreen(checker: checker),
    ),
  );
}

void main() {
  testWidgets('shows every past release, oldest and all, not just the newest', (
    tester,
  ) async {
    final checker = UpdateChecker(
      currentVersion: '0.3.0',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {'tag_name': 'v0.3.0', 'draft': false, 'body': '- latest thing'},
            {'tag_name': 'v0.1.0', 'draft': false, 'body': '- ancient thing'},
          ]),
          200,
        ),
      ),
    );
    addTearDown(checker.close);

    await _pump(tester, checker);
    await tester.pumpAndSettle();

    expect(find.text('Version 0.3.0'), findsOneWidget);
    expect(find.text('latest thing'), findsOneWidget);
    expect(find.text('Version 0.1.0'), findsOneWidget);
    expect(find.text('ancient thing'), findsOneWidget);
  });

  testWidgets('a failed fetch says so instead of showing a blank screen', (
    tester,
  ) async {
    final checker = UpdateChecker(
      currentVersion: '0.3.0',
      client: MockClient((_) async => http.Response('', 500)),
    );
    addTearDown(checker.close);

    await _pump(tester, checker);
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Couldn't load past versions. Check your connection and try again.",
      ),
      findsOneWidget,
    );
  });
}
