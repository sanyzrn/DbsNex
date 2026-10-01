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

  group('a guarded field (the settings search)', () {
    late FocusNode search;
    late List<String> pressed;

    setUp(() {
      search = FocusNode();
      pressed = [];
    });
    tearDown(() => search.dispose());

    Future<void> showGuarded(
      WidgetTester tester, {
      double keyboard = 300,
      bool guarded = true,
    }) async {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);
      final page = ListView(
        children: [
          TextField(
            key: const ValueKey('search'),
            focusNode: search,
            decoration: InputDecoration(
              suffixIcon: IconButton(
                tooltip: 'clear',
                onPressed: () => pressed.add('clear'),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('a setting'),
            value: false,
            onChanged: (_) => pressed.add('setting'),
          ),
          Listener(
            onPointerDown: (_) => pressed.add('raw listener'),
            child: const SizedBox(height: 120, child: Text('listened')),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => NexKeyboardDismisser(child: child!),
          home: Scaffold(
            body: guarded
                ? NexGuardedField(focusNode: search, child: page)
                : page,
          ),
        ),
      );
      search.requestFocus();
      await tester.pump();
    }

    testWidgets('a touch on a setting only closes the keyboard', (
      tester,
    ) async {
      await showGuarded(tester);

      await tester.tap(find.text('a setting'));
      await tester.pump();
      expect(pressed, isEmpty);
      expect(search.hasFocus, isFalse);

      search.requestFocus();
      await tester.pump();
      await tester.tap(find.text('listened'));
      await tester.pump();
      expect(pressed, isEmpty, reason: 'nothing under it hears the touch');

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.tap(find.text('a setting'));
      await tester.pump();
      expect(pressed, ['setting'], reason: 'the next touch is ordinary');
    });

    testWidgets('the field and its clear button work, and a touch in it '
        'never drops focus, not even while the finger is down', (tester) async {
      await showGuarded(tester);

      final press = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('search'))),
      );
      await tester.pump();
      expect(search.hasFocus, isTrue);
      await press.up();
      await tester.pump();
      expect(search.hasFocus, isTrue);

      await tester.tap(find.byTooltip('clear'));
      await tester.pump();
      expect(pressed, ['clear']);
    });

    testWidgets('any other field is unguarded: a touch outside it does what '
        'it touches, as picking a tag with the keyboard up must', (
      tester,
    ) async {
      await showGuarded(tester, guarded: false);

      await tester.tap(find.text('a setting'));
      await tester.pump();
      expect(pressed, ['setting']);

      final press = await tester.startGesture(
        tester.getCenter(find.text('listened')),
      );
      await tester.pump();
      expect(pressed, ['setting', 'raw listener']);
      await press.up();
    });
  });
}
