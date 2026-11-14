import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/nex_time_picker.dart';
import 'package:nex_ui/nex_ui.dart';

/// The Jalali picker, as the owner used it to set 27 Bahman 1365 (2.7.1):
/// choosing a year and a month takes the chosen day along, so OK gives back
/// the month on screen and not the day the picker opened on.
void main() {
  Future<DateTime?> pick(
    WidgetTester tester,
    Future<void> Function() choose,
  ) async {
    DateTime? result;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await nexPickDate(
                  context,
                  initial: DateTime(2026, 11, 14),
                  first: DateTime(1900),
                  last: DateTime(2100, 12, 31),
                  solar: true,
                );
              },
              child: const Text('Pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    await choose();
    await tester.tap(find.text('تأیید').last);
    await tester.pumpAndSettle();
    return result;
  }

  /// Opens the list showing [current] and taps [next] in it, dragging the
  /// list toward earlier entries ([up]) or later ones until it is built.
  Future<void> choose(
    WidgetTester tester,
    String current,
    String next, {
    bool up = false,
  }) async {
    await tester.tap(find.text(current).last);
    await tester.pumpAndSettle();
    final menu = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    for (var i = 0; i < 40 && find.text(next).evaluate().isEmpty; i++) {
      await tester.drag(menu.last, Offset(0, up ? 200 : -200));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(next).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a year and a month from the lists, then OK', (tester) async {
    final picked = await pick(tester, () async {
      await choose(tester, '۱۴۰۵', '۱۳۶۵', up: true);
      await choose(tester, 'آبان', 'بهمن');
    });
    // 23 Aban 1405 opened; 23 Bahman 1365 is what is on screen.
    expect(picked, DateTime(1987, 2, 12));
  });

  testWidgets('and then the day itself', (tester) async {
    final picked = await pick(tester, () async {
      await choose(tester, '۱۴۰۵', '۱۳۶۵', up: true);
      await choose(tester, 'آبان', 'بهمن');
      await tester.tap(find.text('۲۷').last);
      await tester.pump();
    });
    expect(picked, DateTime(1987, 2, 16));
  });

  testWidgets('a 31st carried into a 30-day month is its last day', (
    tester,
  ) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await nexPickDate(
                  context,
                  // 31 Shahrivar 1405.
                  initial: DateTime(2026, 9, 22),
                  first: DateTime(1900),
                  last: DateTime(2100, 12, 31),
                  solar: true,
                );
              },
              child: const Text('Pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ماه بعد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأیید').last);
    await tester.pumpAndSettle();
    // 30 Mehr 1405.
    expect(result, DateTime(2026, 10, 22));
  });
}
