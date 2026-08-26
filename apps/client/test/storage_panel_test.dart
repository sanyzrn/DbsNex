import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_data/nex_data.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/storage_panel.dart';

/// The row this replaces said "Storage — 41 MB" and stopped: a number nobody
/// can act on, and the wrong number besides, because it left out the offline
/// model — which on an install that has one is larger than everything else
/// together by an order of magnitude.
void main() {
  Future<void> pump(WidgetTester tester, StorageSnapshot snapshot) =>
      tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StoragePanel(snapshot: snapshot)),
        ),
      );

  const mb = 1024 * 1024;

  testWidgets('the model is counted, and named', (tester) async {
    await pump(
      tester,
      const StorageSnapshot(
        notes: 12,
        database: 2 * mb,
        images: 8 * mb,
        audio: 4 * mb,
        otherMedia: 0,
        backups: 1 * mb,
      ).withModels(2000 * mb),
    );

    expect(find.text('Offline model'), findsOneWidget);
    // 2015 MB, which formats as GB — the point being that the total moved by
    // the model's size rather than reporting the 15 MB it used to.
    expect(find.textContaining('GB'), findsWidgets);
  });

  testWidgets('a part with nothing in it gets no row', (tester) async {
    await pump(
      tester,
      const StorageSnapshot(
        notes: 3,
        database: 1 * mb,
        images: 0,
        audio: 0,
        otherMedia: 0,
        backups: 0,
      ),
    );

    // Nothing has been recorded or photographed, so the legend does not carry
    // two rows saying zero.
    expect(find.text('Photos'), findsNothing);
    expect(find.text('Recordings'), findsNothing);
    expect(find.text('Notes and index'), findsOneWidget);
  });

  testWidgets('an empty library says so instead of drawing a bar of one', (
    tester,
  ) async {
    await pump(
      tester,
      const StorageSnapshot(
        notes: 0,
        database: 0,
        images: 0,
        audio: 0,
        otherMedia: 0,
        backups: 0,
      ),
    );

    expect(find.text('Nothing stored yet.'), findsOneWidget);
  });
}
