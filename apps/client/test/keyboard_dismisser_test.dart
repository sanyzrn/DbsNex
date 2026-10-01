import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/widgets/keyboard_dismisser.dart';

/// While typing, the first touch outside what is being typed only puts the
/// keyboard away (ADR-038).
///
/// The claim worth a test is both halves at once: the touch beside the field
/// closes the keyboard *and does nothing else* — the birthday's clear button
/// a name was being typed above is not pressed — while the touches that
/// belong to the typing (the field, its clear button, Send, another field,
/// the dialog it sits in) still work with one tap.
void main() {
  late FocusNode field;
  late TextEditingController text;
  late List<String> pressed;

  setUp(() {
    field = FocusNode();
    text = TextEditingController(text: 'Sara');
    pressed = [];
  });

  tearDown(() {
    field.dispose();
    text.dispose();
  });

  Future<void> show(
    WidgetTester tester, {
    double keyboard = 300,
    bool focus = true,
  }) async {
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => NexKeyboardDismisser(child: child!),
        home: Scaffold(
          body: ListView(
            children: [
              TextField(
                key: const ValueKey('name'),
                focusNode: field,
                controller: text,
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                    tooltip: 'clear name',
                    onPressed: () => pressed.add('clear name'),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
              const TextField(key: ValueKey('other')),
              ListTile(
                title: const Text('birthday'),
                trailing: IconButton(
                  tooltip: 'remove birthday',
                  onPressed: () => pressed.add('remove birthday'),
                  icon: const Icon(Icons.close),
                ),
              ),
              Listener(
                onPointerDown: (_) => pressed.add('raw listener'),
                child: const SizedBox(
                  height: 120,
                  child: Center(child: Text('listened')),
                ),
              ),
              NexTypingAction(
                child: FilledButton(
                  onPressed: () => pressed.add('save'),
                  child: const Text('save'),
                ),
              ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                      content: const TextField(
                        key: ValueKey('dialog field'),
                        autofocus: true,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            pressed.add('dialog ok');
                            Navigator.pop(dialog);
                          },
                          child: const Text('ok'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('open dialog'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (focus) {
      field.requestFocus();
      await tester.pump();
      expect(field.hasFocus, isTrue, reason: 'the field should start focused');
    }
  }

  testWidgets('a touch on a button beside the field only closes the keyboard', (
    tester,
  ) async {
    await show(tester);

    await tester.tap(find.byTooltip('remove birthday'));
    await tester.pump();

    expect(field.hasFocus, isFalse);
    expect(pressed, isEmpty, reason: 'the birthday must not be removed');

    // The keyboard is down now; the next touch is an ordinary one.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.tap(find.byTooltip('remove birthday'));
    await tester.pump();
    expect(pressed, ['remove birthday']);
  });

  testWidgets('nothing under the finger hears about it, not even a raw '
      'pointer listener', (tester) async {
    await show(tester);

    await tester.tap(find.text('listened'));
    await tester.pump();

    expect(pressed, isEmpty);
    expect(field.hasFocus, isFalse);
  });

  testWidgets('a drag outside does not scroll the page under the keyboard', (
    tester,
  ) async {
    await show(tester);
    final before = tester.getTopLeft(find.text('birthday'));

    await tester.drag(find.text('listened'), const Offset(0, -200));
    await tester.pump();

    expect(tester.getTopLeft(find.text('birthday')), before);
    expect(field.hasFocus, isFalse);
  });

  testWidgets('the field and its own clear button keep working', (
    tester,
  ) async {
    await show(tester);

    await tester.tap(find.byKey(const ValueKey('name')));
    await tester.pump();
    expect(field.hasFocus, isTrue);

    await tester.tap(find.byTooltip('clear name'));
    await tester.pump();
    expect(pressed, ['clear name']);
  });

  testWidgets('another field takes the typing with one tap', (tester) async {
    await show(tester);

    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();

    expect(field.hasFocus, isFalse);
    final other = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('other')),
        matching: find.byType(EditableText),
      ),
    );
    expect(other.focusNode.hasFocus, isTrue);
  });

  testWidgets('Save, marked as acting on what is typed, works with one tap', (
    tester,
  ) async {
    await show(tester);

    await tester.tap(find.text('save'));
    await tester.pump();

    expect(pressed, ['save']);
  });

  testWidgets('in a dialog, its buttons work and the dimmed screen only '
      'closes the keyboard', (tester) async {
    await show(tester, focus: false);
    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isA<Focus>(),
      reason: 'the dialog field should hold focus',
    );

    // The dimmed screen, well away from the dialog.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.tap(find.byKey(const ValueKey('dialog field')));
    await tester.pump();
    await tester.tap(find.text('ok'));
    await tester.pumpAndSettle();
    expect(pressed, ['dialog ok']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('with no keyboard up, every touch is an ordinary one', (
    tester,
  ) async {
    await show(tester, keyboard: 0);

    await tester.tap(find.byTooltip('remove birthday'));
    await tester.pump();

    expect(pressed, ['remove birthday']);
  });
}
