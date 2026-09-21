import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/widgets/keyboard_dismisser.dart';

/// The way out of the keyboard.
///
/// Three claims, and the middle one is the one worth a test: this catches the
/// taps nothing else wanted, and nothing else. A tap-anywhere handler that
/// also eats the tap on the save button is not a convenience, it is a bug
/// people cannot describe.
void main() {
  late FocusNode field;
  late bool saved;

  setUp(() {
    field = FocusNode();
    saved = false;
  });

  tearDown(() => field.dispose());

  Future<void> show(WidgetTester tester, {required double keyboard}) async {
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: NexKeyboardDismisser(
          child: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: field),
                const SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: Center(child: Text('empty')),
                ),
                ElevatedButton(
                  onPressed: () => saved = true,
                  child: const Text('save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    field.requestFocus();
    await tester.pump();
    expect(field.hasFocus, isTrue, reason: 'the field should start focused');
  }

  testWidgets('a tap on nothing puts the keyboard away', (tester) async {
    await show(tester, keyboard: 300);
    await tester.tap(find.text('empty'));
    await tester.pump();
    expect(field.hasFocus, isFalse);
  });

  testWidgets('a tap on the field stays with the field', (tester) async {
    await show(tester, keyboard: 300);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    // The tap belongs to the deepest recognizer that wants it, and this is
    // the shallowest there is. Were that not so, moving the caret would shut
    // the keyboard mid-sentence.
    expect(field.hasFocus, isTrue);
  });

  testWidgets('a tap on a button stays with the button', (tester) async {
    await show(tester, keyboard: 300);
    await tester.tap(find.text('save'));
    await tester.pump();
    expect(saved, isTrue);
  });

  testWidgets('with no keyboard up, focus is left alone', (tester) async {
    await show(tester, keyboard: 0);
    await tester.tap(find.text('empty'));
    await tester.pump();
    // On a desktop or with a hardware keyboard there is nothing covering the
    // screen and nothing to dismiss, so a stray tap should not be quietly
    // taking focus off whatever had it.
    expect(field.hasFocus, isTrue);
  });
}
