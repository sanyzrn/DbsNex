import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// Copying a selection that spans several text widgets keeps the line
/// breaks between them.
void main() {
  late List<String> clipboard;

  setUp(() {
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  Future<String> copyAll(WidgetTester tester, Widget child) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(focusNode: focus, child: child),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    return clipboard.last;
  }

  testWidgets('a note mixing Persian and English lines keeps its lines', (
    tester,
  ) async {
    const text = 'Shopping list\nشیر و نان\nand eggs';
    final copied = await copyAll(tester, const NexTextSurface(text));
    expect(copied, text);
  });

  testWidgets('an empty line copies as a line, not as a zero-width space', (
    tester,
  ) async {
    // The empty line is *drawn* as a zero-width space so it keeps its
    // height; what it copies as is the newline between its neighbours.
    const text = 'First\n\nThird';
    final copied = await copyAll(tester, const NexTextSurface(text));
    expect(copied, text);
    expect(copied.contains('\u200B'), isFalse);
  });

  testWidgets(
    'lines whose boxes overlap by more than a pixel still copy as lines',
    (tester) async {
      // Persian descenders and large text scales make neighbouring line
      // boxes overlap by more than the one pixel the old row test allowed;
      // those copies came back glued with spaces. A two-pixel overlap stands
      // in for that here — the centres, which the row test reads now, are
      // still a good half-line apart.
      final copied = await copyAll(
        tester,
        Column(
          children: [
            const NexTextSurface.line('First'),
            Transform.translate(
              offset: const Offset(0, -2),
              child: const NexTextSurface.line('Second'),
            ),
          ],
        ),
      );
      expect(copied.split('\n'), ['First', 'Second']);
    },
  );

  testWidgets('Markdown keeps a line break between its blocks', (tester) async {
    final copied = await copyAll(
      tester,
      const NexMarkdown(
        '# Title\n\nFirst paragraph.\n\n- one\n- two',
        // As the detail sheet uses it: inside its own SelectionArea.
        selectable: false,
      ),
    );
    expect(copied.split('\n'), ['Title', 'First paragraph.', '• one', '• two']);
  });
}
