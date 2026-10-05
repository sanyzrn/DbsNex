import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/empty_timeline.dart';

/// An empty page offers the first thing to do, not only an explanation
/// (1.94.0).
void main() {
  testWidgets('each example row on the empty timeline starts that capture', (
    tester,
  ) async {
    final tapped = <String>[];
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EmptyTimeline(
            onWrite: () => tapped.add('write'),
            onSpeak: () => tapped.add('speak'),
            onPhotograph: () => tapped.add('photo'),
          ),
        ),
      ),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(EmptyTimeline)),
    );
    await tester.tap(find.text(l10n.emptyType));
    await tester.tap(find.text(l10n.emptySpeak));
    await tester.tap(find.text(l10n.emptyPhotograph));
    expect(tapped, ['write', 'speak', 'photo']);
  });
}
