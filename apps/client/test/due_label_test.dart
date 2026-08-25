import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/card_strings.dart';
import 'package:nex_client/widgets/due_label.dart';

Note _noteDue(DateTime? due) {
  final now = DateTime.now().toUtc();
  return Note(
    id: 'n1',
    type: NoteType.text,
    content: 'call the plumber',
    createdAt: now,
    updatedAt: now,
    dueAt: due?.toUtc(),
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );
}

/// A reminder that had been set was a bell and nothing else: the card said one
/// existed, the sheet said one existed, and neither said when. The only thing
/// anyone could do to a reminder they could not read was delete it.
void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('the countdown on a card', () {
    test('says how long is left, in the unit that reads at that distance', () {
      final now = DateTime.now();
      // Rounded up throughout, the same way the confirmation does: the number
      // people check against is when it *will* go off, and undershooting reads
      // as the app being wrong. Every case here is a hair under the round
      // figure by the time the function reads the clock.
      expect(
        nexDueCountdown(en, now.add(const Duration(minutes: 30))),
        '30 minutes',
      );
      expect(nexDueCountdown(en, now.add(const Duration(hours: 3))), '3 hours');
      expect(
        nexDueCountdown(en, now.add(const Duration(days: 2, hours: 2))),
        '3 days',
      );
    });

    test('a reminder whose time has passed says so', () {
      final past = DateTime.now().subtract(const Duration(hours: 2));
      expect(nexDueCountdown(en, past), 'Overdue');
    });
  });

  group('the exact time, where there is room for it', () {
    Future<String> label(WidgetTester tester, DateTime due) async {
      late String result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              result = nexDueExact(context, due);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('today and tomorrow are named, not dated', (tester) async {
      final today = DateTime.now().copyWith(hour: 21, minute: 0);
      expect(await label(tester, today), startsWith('Today at'));

      final tomorrow = DateTime.now()
          .add(const Duration(days: 1))
          .copyWith(hour: 9, minute: 0);
      expect(await label(tester, tomorrow), startsWith('Tomorrow at'));
    });

    testWidgets('anything further off carries its date', (tester) async {
      final later = DateTime.now()
          .add(const Duration(days: 9))
          .copyWith(hour: 9, minute: 0);
      final text = await label(tester, later);
      expect(text, contains(' at '));
      expect(text, isNot(startsWith('Today')));
      expect(text, isNot(startsWith('Tomorrow')));
    });
  });

  group('the card', () {
    Future<void> pumpCard(WidgetTester tester, Note note) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  NoteCard(note: note, strings: nexCardStrings(context)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows when the reminder is, not just that there is one', (
      tester,
    ) async {
      await pumpCard(
        tester,
        _noteDue(DateTime.now().add(const Duration(hours: 3))),
      );
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(find.textContaining('3'), findsWidgets);
    });

    testWidgets('a note with no reminder carries no bell at all', (
      tester,
    ) async {
      await pumpCard(tester, _noteDue(null));
      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
    });
  });
}
