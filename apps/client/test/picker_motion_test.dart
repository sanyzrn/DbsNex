import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_time_picker.dart';
import 'package:nex_ui/nex_ui.dart';

/// The time and date pickers are the clock app's own dialogs — but they
/// arrive the way this app asks questions, on its beat and its scrim, not
/// on Flutter's 150ms fade over raw black54.
void main() {
  Future<void> openTime(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => nexPickTime(
                context,
                initial: const TimeOfDay(hour: 9, minute: 0),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  testWidgets('the time picker arrives on the app beat', (tester) async {
    await openTime(tester);
    final route = ModalRoute.of(tester.element(find.byType(Dialog)))!;
    expect(route.transitionDuration, NexMotion.enter);
    expect(route.reverseTransitionDuration, NexMotion.exit);

    // Still arriving half way through, and it is a real picker when it
    // lands: OK answers with a time.
    await tester.pump(NexMotion.enter ~/ 2);
    expect(route.animation!.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('the date picker arrives on the app beat', (tester) async {
    final day = DateTime(2026, 8, 24);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => nexPickDate(
                context,
                initial: day,
                first: day,
                last: day.add(const Duration(days: 365)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    final route = ModalRoute.of(tester.element(find.byType(Dialog)))!;
    expect(route.transitionDuration, NexMotion.enter);
    expect(route.reverseTransitionDuration, NexMotion.exit);
    await tester.pumpAndSettle();

    // A day outside the window is clamped to the window, exactly as
    // showDatePicker did, so the calendar always has something to show.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('a date past the end of the window opens on the last day', (
    tester,
  ) async {
    final first = DateTime(2026, 8, 24);
    final last = first.add(const Duration(days: 30));
    late DateTime? answered;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                answered = await nexPickDate(
                  context,
                  initial: last.add(const Duration(days: 400)),
                  first: first,
                  last: last,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Nothing asserts about the out-of-range date: the window's last day is
    // what the calendar opens on, and OK hands it back.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(answered, last);
    await tester.pumpWidget(const SizedBox());
  });
}
