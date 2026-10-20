import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_dialog.dart';

/// A tap on the dimmed area closes every sheet, including the ones that
/// guard unsaved work — through the editor's own PopScope, so a clean editor
/// closes and a dirty one stays to ask.
void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required bool guarded,
    bool canPop = true,
    void Function()? onBlocked,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => nexShowSheet<void>(
                  context: context,
                  dismissible: !guarded,
                  swipeToClose: guarded,
                  builder: (_) => PopScope(
                    canPop: canPop,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) onBlocked?.call();
                    },
                    child: const SizedBox(
                      height: 200,
                      child: Center(child: Text('Sheet body')),
                    ),
                  ),
                ),
                child: const Text('page underneath'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('page underneath'));
    await tester.pumpAndSettle();
    expect(find.text('Sheet body'), findsOneWidget);
  }

  Future<void> tapOutside(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
  }

  testWidgets('a tap outside closes an ordinary sheet', (tester) async {
    await openSheet(tester, guarded: false);
    await tapOutside(tester);
    expect(find.text('Sheet body'), findsNothing);
  });

  testWidgets('a tap outside closes a clean editor sheet', (tester) async {
    await openSheet(tester, guarded: true);
    await tapOutside(tester);
    expect(find.text('Sheet body'), findsNothing);
  });

  testWidgets('a tap outside asks a dirty editor sheet, which stays', (
    tester,
  ) async {
    var asked = 0;
    await openSheet(
      tester,
      guarded: true,
      canPop: false,
      onBlocked: () => asked++,
    );
    await tapOutside(tester);
    expect(find.text('Sheet body'), findsOneWidget);
    expect(asked, 1);
  });
}
