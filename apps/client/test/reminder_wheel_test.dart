import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/reminder_wheel.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// The sheet's whole promise is that the button says what it is about to do,
/// so that is what these check: the wheels and the sentence agree, and the one
/// time they cannot agree — a moment already gone — the button will not fire.
void main() {
  // A Monday, mid-morning, so "today" and "tomorrow" are unambiguous and the
  // hour has room to move in both directions.
  final now = DateTime(2026, 9, 7, 10, 15);

  Note note({DateTime? due, NoteRepeat repeat = NoteRepeat.once}) => Note(
    id: 'n1',
    type: NoteType.text,
    content: 'ring me',
    createdAt: now,
    updatedAt: now,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
    dueAt: due?.toUtc(),
    dueRepeat: repeat,
  );

  DateTime? submitted;
  var cleared = false;

  Future<void> pump(WidgetTester tester, Note value) async {
    submitted = null;
    cleared = false;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Pinned through `builder`, not by wrapping `home` in a bare
        // MediaQueryData — that one replaces the whole thing, size included,
        // and lays the sheet out in a window zero pixels across.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: Scaffold(
          body: ReminderWheel(
            note: value,
            now: now,
            onSubmit: (when, _) => submitted = when,
            onClear: () => cleared = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('it opens an hour out and says so', (tester) async {
    await pump(tester, note());

    // 10:15 + an hour, and the button spells it out rather than saying "Set".
    expect(find.text('Remind today at 11:15'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    expect(submitted, DateTime(2026, 9, 7, 11, 15));
  });

  testWidgets('an existing reminder is what it opens on', (tester) async {
    await pump(tester, note(due: DateTime(2026, 9, 8, 7, 30)));

    expect(find.text('Remind tomorrow at 07:30'), findsOneWidget);
  });

  testWidgets('an overdue reminder does not open onto a dead button', (
    tester,
  ) async {
    // Anchoring on the stored time would put the wheels in the past, where
    // the button is disabled — with nothing on screen saying why.
    await pump(tester, note(due: DateTime(2026, 9, 1, 9)));

    expect(find.text('Remind today at 11:15'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a shortcut moves the wheels instead of closing the sheet', (
    tester,
  ) async {
    await pump(tester, note());

    await tester.tap(find.text('Tomorrow morning'));
    await tester.pumpAndSettle();

    expect(find.text('Remind tomorrow at 09:00'), findsOneWidget);
    expect(submitted, isNull, reason: 'a shortcut is not a confirmation');
  });

  testWidgets('a time already gone by cannot be set', (tester) async {
    await pump(tester, note());

    // Roll the hour back three rows: 11:15 becomes 08:15, this morning. The
    // scheduler drops a past-due one-off, so a live button here would report
    // success for an alarm that never exists.
    //
    // Moved by hand rather than with `drag`, which releases at speed: the
    // hour column loops, so a fling that overshoots does not stop at 00 — it
    // comes round to the evening and lands on a time that is still ahead.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ReminderWheel.hourKey)),
    );
    for (var step = 0; step < 12; step++) {
      await gesture.moveBy(const Offset(0, 11));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('That moment has already gone by'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('clearing is offered only when there is something to clear', (
    tester,
  ) async {
    await pump(tester, note());
    expect(find.text('Remove reminder'), findsNothing);

    await pump(tester, note(due: DateTime(2026, 9, 8, 7, 30)));
    await tester.tap(find.text('Remove reminder'));
    expect(cleared, isTrue);
  });
}
