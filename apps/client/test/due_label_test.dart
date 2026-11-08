import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/card_strings.dart';
import 'package:nex_client/widgets/due_label.dart';

Note _noteDue(DateTime? due) {
  final now = DateTime.utc(2026, 10, 14, 12);
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
  final fixedNow = DateTime(2026, 10, 14, 12);
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('the countdown on a card', () {
    test('says how long is left, in the unit that reads at that distance', () {
      final now = fixedNow;
      // Rounded up throughout, the same way the confirmation does: the number
      // people check against is when it *will* go off, and undershooting reads
      // as the app being wrong. The reference instant is fixed so these
      // assertions do not depend on elapsed test time.
      //
      // Short forms, not the sentences the confirmation uses: this shares one
      // line with the note's own words, and "13 hours" took enough of it to
      // push them off the card.
      expect(
        nexDueCountdown(en, now.add(const Duration(minutes: 30)), now: now),
        '30m',
      );
      expect(
        nexDueCountdown(en, now.add(const Duration(hours: 3)), now: now),
        '3h',
      );
      expect(
        nexDueCountdown(
          en,
          now.add(const Duration(days: 2, hours: 2)),
          now: now,
        ),
        '3d',
      );
    });

    test('a reminder whose time has passed says so', () {
      final past = fixedNow.subtract(const Duration(hours: 2));
      expect(nexDueCountdown(en, past, now: fixedNow), 'Overdue');
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
              result = nexDueExact(context, due, now: fixedNow);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('today and tomorrow are named, not dated', (tester) async {
      final today = fixedNow.copyWith(hour: 21, minute: 0);
      expect(await label(tester, today), startsWith('Today at'));

      final tomorrow = fixedNow
          .add(const Duration(days: 1))
          .copyWith(hour: 9, minute: 0);
      expect(await label(tester, tomorrow), startsWith('Tomorrow at'));
    });

    testWidgets('anything further off carries its date', (tester) async {
      final later = fixedNow
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

    testWidgets('keeps a reminder icon with its label temporarily hidden', (
      tester,
    ) async {
      await pumpCard(tester, _noteDue(fixedNow.add(const Duration(hours: 3))));
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(find.textContaining('3'), findsNothing);
    });

    testWidgets('a note with no reminder carries no bell at all', (
      tester,
    ) async {
      await pumpCard(tester, _noteDue(null));
      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
    });
  });
  for (final lang in ['en', 'fa']) {
    for (final repeat in [NoteRepeat.daily, NoteRepeat.weekly]) {
      testWidgets(
        '$lang $repeat keeps full schedule accessible with an icon-only mark',
        (tester) async {
          final due = DateTime(2026, 10, 14, 9, 5);
          late String label;
          late String description;
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(lang),
              theme: nexLightTheme(fontFamily: nexFontFor(Locale(lang))),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MediaQuery(
                data: const MediaQueryData(alwaysUse24HourFormat: true),
                child: Scaffold(
                  body: Builder(
                    builder: (context) {
                      label = nexDueCardLabel(context, due.toUtc(), repeat);
                      description = nexDueCardDescription(
                        context,
                        due.toUtc(),
                        repeat,
                      );
                      final base = _noteDue(due);
                      return NoteCard(
                        note: base.copyWith(dueRepeat: repeat),
                        strings: nexCardStrings(context),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(label, contains(lang == 'fa' ? '۹:۰۵' : '09:05'));
          expect(find.text(label), findsNothing);
          expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
          expect(
            description,
            contains(
              lang == 'fa'
                  ? (repeat == NoteRepeat.daily ? 'هر روز' : 'هر هفته')
                  : (repeat == NoteRepeat.daily ? 'Every day' : 'Every week'),
            ),
          );
          expect(find.bySemanticsLabel(description), findsOneWidget);
          final icon = tester.getRect(find.byIcon(Icons.repeat_rounded));
          // The centre sits on the outer rim; the upper half remains
          // interactive within the original leading hit-test bounds.
          await tester.longPressAt(icon.topCenter + const Offset(0, 2));
          await tester.pumpAndSettle();
          expect(find.text(description), findsOneWidget);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
  testWidgets(
    'icon-only reminder and attachment marks fit a narrow large-text card',
    (tester) async {
      final due = DateTime(2026, 10, 14, 9, 5);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: nexLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              alwaysUse24HourFormat: true,
              textScaler: TextScaler.linear(1.9),
            ),
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: Builder(
                  builder: (context) => NoteCard(
                    note: _noteDue(
                      due,
                    ).copyWith(dueRepeat: NoteRepeat.daily, attachmentCount: 2),
                    strings: nexCardStrings(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('09:05'),
        findsNothing,
        reason: 'status labels are temporarily hidden',
      );
      expect(find.text('+2'), findsNothing);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
