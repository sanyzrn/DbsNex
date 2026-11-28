import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/keyboard_dismisser.dart';
import 'package:nex_client/widgets/nex_text_field.dart';
import 'package:nex_client/widgets/nex_paragraph_editor.dart';
import 'package:super_editor/src/test/ime.dart';
import 'package:super_editor/super_editor.dart';

import 'support/text_input.dart';

List<TextDirection> _directions(WidgetTester tester) => [
  for (final element in find.byType(ParagraphComponent).evaluate())
    (element.widget as ParagraphComponent).viewModel.textDirection,
];

void main() {
  Future<void> pump(WidgetTester tester, Widget field) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: field)),
      ),
    );
    await tester.pump();
  }

  testWidgets('no platform view is created, on any platform', (tester) async {
    // The whole point of 2.9.4: nothing embeds the platform's editor any
    // more. Were one to come back, every keyboard fix since would be
    // rebuilt on the switch that broke them.
    var creates = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') creates++;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );
    try {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        final controller = TextEditingController(text: 'سلام');
        addTearDown(controller.dispose);
        await pump(tester, NexTextField(controller: controller, maxLines: 5));
        await enterNexText(tester, nexInputs(), 'typing in ${platform.name}');
        expect(creates, 0, reason: 'the editor embedded a view on $platform');
        expect(find.byType(NexParagraphEditor), findsOneWidget);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('focusing the second field never asks the keyboard to close', (
    tester,
  ) async {
    // The strongest form a host test can express of the transition that
    // used to close the keyboard: Prompt Studio's title into its body,
    // under the dismisser, with the keyboard up. One editor owns the
    // input connection for the whole app, so a move between fields is not
    // a handoff, and `TextInput.hide` is never sent.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    final title = FocusNode();
    final body = FocusNode();
    addTearDown(title.dispose);
    addTearDown(body.dispose);
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    addTearDown(titleController.dispose);
    addTearDown(bodyController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: NexKeyboardDismisser(
          child: Scaffold(
            body: Column(
              children: [
                NexTextField(
                  key: const ValueKey('title'),
                  controller: titleController,
                  focusNode: title,
                ),
                NexTextField(
                  key: const ValueKey('body'),
                  controller: bodyController,
                  focusNode: body,
                  maxLines: 5,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('title')));
    await tester.pump();
    expect(title.hasFocus, isTrue);
    tester.testTextInput.log.clear();
    await tester.tap(find.byKey(const ValueKey('body')));
    await tester.pumpAndSettle();
    expect(body.hasFocus, isTrue);
    expect(
      tester.testTextInput.log.map((call) => call.method),
      isNot(contains('TextInput.hide')),
      reason: 'one editor never hands the keyboard off',
    );
  });

  testWidgets('focusing a plain field never asks the keyboard to close', (
    tester,
  ) async {
    // The Habits transition: the note's editor into the name field. The
    // handoff raced its own teardown on exactly this mixed pair, from the
    // platform-view client to the framework's. Both are the framework's
    // now, so the pair is just another move.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    final note = FocusNode();
    final name = FocusNode();
    addTearDown(note.dispose);
    addTearDown(name.dispose);
    final noteController = TextEditingController();
    final nameController = TextEditingController();
    addTearDown(noteController.dispose);
    addTearDown(nameController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: NexKeyboardDismisser(
          child: Scaffold(
            body: Column(
              children: [
                NexTextField(
                  key: const ValueKey('note'),
                  controller: noteController,
                  focusNode: note,
                  maxLines: 5,
                ),
                TextField(
                  key: const ValueKey('name'),
                  controller: nameController,
                  focusNode: name,
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('note')));
    await tester.pump();
    expect(note.hasFocus, isTrue);
    tester.testTextInput.log.clear();
    await tester.tap(find.byKey(const ValueKey('name')));
    await tester.pumpAndSettle();
    expect(name.hasFocus, isTrue);
    expect(
      tester.testTextInput.log.map((call) => call.method),
      isNot(contains('TextInput.hide')),
    );
  });

  testWidgets('moving or reversing a selection keeps each paragraph in place', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'سلام\nhello\nدوباره');
    addTearDown(controller.dispose);
    await pump(
      tester,
      NexTextField(controller: controller, maxLines: 5, autofocus: true),
    );
    final editor = find.byType(SuperEditor);
    final state = tester.state(editor);
    const directions = [
      TextDirection.rtl,
      TextDirection.ltr,
      TextDirection.rtl,
    ];
    expect(_directions(tester), directions);
    for (final selection in [
      const TextSelection.collapsed(offset: 7),
      const TextSelection(baseOffset: 9, extentOffset: 2),
      const TextSelection.collapsed(offset: 2),
    ]) {
      controller.selection = selection;
      await tester.pump();
      expect(_directions(tester), directions);
      expect(tester.state(editor), same(state));
      expect(tester.widget<SuperEditor>(editor).focusNode!.hasFocus, isTrue);
    }
  });

  testWidgets('a fixed direction is kept, whatever is typed', (tester) async {
    // Code is the one field that is always left to right, even in a
    // Persian interface and even when its comments are Persian.
    final controller = TextEditingController(text: 'کد');
    addTearDown(controller.dispose);
    await pump(
      tester,
      NexTextField(
        controller: controller,
        textDirection: TextDirection.ltr,
        maxLines: 5,
      ),
    );
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('a monospace field draws a fixed-width face', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(
      tester,
      NexTextField(
        controller: controller,
        monospace: true,
        style: const TextStyle(fontSize: 20),
        maxLines: 5,
      ),
    );
    final style = tester.widget<TextField>(find.byType(TextField)).style!;
    expect(style.fontSize, 20, reason: 'the given style is the base');
    expect(style.fontFamily, 'monospace');
    expect(style.fontFamilyFallback, contains('Courier New'));
  });

  testWidgets('code is not prose: suggestions and smart punctuation stay off', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(tester, NexTextField(controller: controller, monospace: true));
    final code = tester.widget<TextField>(find.byType(TextField));
    expect(code.enableSuggestions, isFalse);
    expect(code.smartDashesType, SmartDashesType.disabled);
    expect(code.smartQuotesType, SmartQuotesType.disabled);
    await pump(tester, NexTextField(controller: controller, maxLines: 3));
    final prose = tester.widget<SuperEditor>(find.byType(SuperEditor));
    expect(prose.imeConfiguration!.enableSuggestions, isTrue);
  });

  testWidgets('typing reaches the controller the same frame', (tester) async {
    // There is no second copy of the text anywhere: what is typed is in
    // the controller the frame it is typed — the whole app reads one
    // truth.
    var changed = '';
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(
      tester,
      NexTextField(
        controller: controller,
        onChanged: (value) {
          changed = value;
        },
      ),
    );
    await enterNexText(tester, nexInputs(), 'typed by nobody');
    expect(controller.text, 'typed by nobody');
    expect(changed, 'typed by nobody');
  });

  testWidgets('a change made in Dart is in the field', (tester) async {
    // The same truth, the other way round: an AI rewrite, a format, a
    // cleared composer writes into the controller, and the editor shows
    // it the same frame — nothing is copied across.
    final controller = TextEditingController(text: 'before');
    addTearDown(controller.dispose);
    await pump(tester, NexTextField(controller: controller, maxLines: 3));
    controller.text = 'changed from Dart';
    await tester.pump();
    expect(find.text('changed from Dart', findRichText: true), findsOneWidget);
  });

  testWidgets('typing and parent rebuilds keep the editor element', (
    tester,
  ) async {
    // The sheets these fields sit in rebuild on every keystroke and every
    // frame of the keyboard's animation. The editor below must keep its
    // element and its config through them all, or a handle being dragged
    // mid-rebuild is a handle torn away.
    var builds = 0;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              builds++;
              return NexTextField(
                controller: controller,
                maxLength: 10,
                onChanged: (_) => setState(() {}),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final before = tester.state(find.byType(SuperEditor));
    await enterNexText(tester, nexInputs(), 'typing');
    await tester.pump();
    expect(builds, greaterThan(1));
    expect(tester.state(find.byType(SuperEditor)), same(before));
    expect(
      tester
          .widget<NexParagraphEditor>(find.byType(NexParagraphEditor))
          .maxLength,
      10,
    );
  });

  testWidgets('Enter sends where the field sends', (tester) async {
    var submitted = '';
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(
      tester,
      NexTextField(
        controller: controller,
        textInputAction: TextInputAction.send,
        onSubmitted: (value) => submitted = value,
      ),
    );
    await enterNexText(tester, nexInputs(), 'the text');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(submitted, 'the text');
  });

  testWidgets('the field honors maxLength', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(
      tester,
      NexTextField(controller: controller, maxLength: 5, maxLines: 3),
    );
    await enterNexText(tester, nexInputs(), 'abcdefgh');
    expect(controller.text, 'abcde');
  });

  testWidgets('inputFormatters run in the field', (tester) async {
    // The capture box's code gestures ride on input formatters now; the
    // field must run them like any TextField would.
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(
      tester,
      NexTextField(
        controller: controller,
        inputFormatters: [FilteringTextInputFormatter.deny(RegExp('x'))],
      ),
    );
    await enterNexText(tester, nexInputs(), 'axbxc');
    expect(controller.text, 'abc');
  });

  test(
    'a private copy sends the selection through its own clipboard',
    () async {
      // The vault's copy goes where onCopy sends it, and a copy moves
      // nothing.
      final controller = TextEditingController(text: 'hello world');
      addTearDown(controller.dispose);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      String? copied;
      await nexPrivateCopy(
        controller,
        (text) async => copied = text,
        cut: false,
      );
      expect(copied, 'hello');
      expect(controller.text, 'hello world');
    },
  );

  test(
    'a private cut removes the text once the copy has gone through',
    () async {
      final controller = TextEditingController(text: 'hello world');
      addTearDown(controller.dispose);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      var changed = '';
      await nexPrivateCopy(
        controller,
        (text) async {},
        cut: true,
        onChanged: (value) => changed = value,
      );
      expect(changed, ' world');
      expect(controller.text, ' world');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    },
  );

  test('a failed copy leaves the text as it was', () async {
    // A clipboard that refuses must not eat the words.
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await nexPrivateCopy(
      controller,
      (text) async => throw Exception('clipboard refused'),
      cut: true,
    );
    expect(controller.text, 'hello world');
  });

  test(
    'a change made while the copy was in flight keeps the newer text',
    () async {
      // A cut may only remove what was copied: if the person kept typing
      // while the clipboard worked, the newer text is the truth.
      final controller = TextEditingController(text: 'hello world');
      addTearDown(controller.dispose);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      final inFlight = Completer<void>();
      final copy = nexPrivateCopy(
        controller,
        (text) async => inFlight.future,
        cut: true,
      );
      controller.text = 'changed mid-flight';
      inFlight.complete();
      await copy;
      expect(controller.text, 'changed mid-flight');
    },
  );

  test('a collapsed selection copies nothing', () async {
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 3);
    var called = false;
    await nexPrivateCopy(controller, (text) async => called = true, cut: true);
    expect(called, isFalse);
    expect(controller.text, 'hello world');
  });

  testWidgets('a composing paragraph keeps its text, composition and focus', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(
      tester,
      NexTextField(controller: controller, maxLines: 5, autofocus: true),
    );
    await showNexKeyboard(tester, nexInputs());
    final editor = find.byType(SuperEditor);
    final state = tester.state(editor);
    final client = imeClientGetter();
    final before = client.currentTextEditingValue!;
    final at = before.selection.extentOffset;
    client.updateEditingValueWithDeltas([
      TextEditingDeltaInsertion(
        oldText: before.text,
        textInserted: 'سلام',
        insertionOffset: at,
        selection: TextSelection.collapsed(offset: at + 4),
        composing: TextRange(start: at, end: at + 4),
      ),
    ]);
    await tester.pump();
    expect(controller.value.composing, const TextRange(start: 0, end: 4));
    expect(controller.text, 'سلام');
    expect(_directions(tester), [TextDirection.rtl]);

    final composed = client.currentTextEditingValue!;
    client.updateEditingValueWithDeltas([
      TextEditingDeltaNonTextUpdate(
        oldText: composed.text,
        selection: composed.selection,
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();
    expect(controller.value.composing, TextRange.empty);
    expect(controller.text, 'سلام');
    expect(tester.state(editor), same(state));
    expect(tester.widget<SuperEditor>(editor).focusNode!.hasFocus, isTrue);
  });

  testWidgets('the decoration is the one it was given', (tester) async {
    // The border, the label, the counter stay Flutter's, drawn around
    // the editor — the one thing a platform editor never gave.
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(
      tester,
      NexTextField(
        controller: controller,
        decoration: const InputDecoration(hintText: 'Write a note'),
        maxLines: 3,
      ),
    );
    expect(
      tester
          .widget<InputDecorator>(find.byType(InputDecorator))
          .decoration
          .hintText,
      'Write a note',
    );
    expect(find.text('Write a note'), findsOneWidget);
  });
}
