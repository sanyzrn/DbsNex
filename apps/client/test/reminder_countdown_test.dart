import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/nex_time_picker.dart';

/// The picker is opened through helpers rather than `showTimePicker` directly,
/// because the app scales its own type and a dial does not survive that. These
/// prove the dialogs come up under the platform's scaling, not Nex's — which
/// is the difference between the app's picker and the one in the clock app.
void main() {
  Widget host({
    required double appScale,
    required Widget Function(BuildContext) child,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, inner) => MediaQuery(
      // Stands in for app.dart's own wrapper, which composes the user's UI
      // scale with the system's.
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(appScale)),
      child: inner!,
    ),
    home: Builder(builder: child),
  );

  testWidgets('the time picker ignores the app-wide type scale', (
    tester,
  ) async {
    late double insidePicker;
    await tester.pumpWidget(
      host(
        appScale: 1.8,
        child: (context) => TextButton(
          onPressed: () => nexPickTime(
            context,
            initial: const TimeOfDay(hour: 9, minute: 0),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Read from inside the dialog: whatever the app is scaling by, the dial
    // is laid out at the platform's own scale.
    insidePicker = MediaQuery.textScalerOf(
      tester.element(find.byType(Dialog).last),
    ).scale(10);
    expect(insidePicker, 10);
  });

  testWidgets('the date picker does too', (tester) async {
    final now = DateTime(2026, 8, 24);
    await tester.pumpWidget(
      host(
        appScale: 0.75,
        child: (context) => TextButton(
          onPressed: () => nexPickDate(
            context,
            initial: now,
            first: now,
            last: now.add(const Duration(days: 365)),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byType(Dialog).last),
      ).scale(10),
      10,
    );
  });
}
