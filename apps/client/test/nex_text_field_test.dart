import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/keyboard_dismisser.dart';
import 'package:nex_client/widgets/nex_text_field.dart';

/// The one editor (ADR-037), the framework's own. No platform view is
/// created on any platform, so no field-to-field transition ever passes
/// through the engine's input-client switch — the thing that closed and
/// reopened the keyboard between fields through 2.9.1–2.9.3. These tests
/// hold that line: typing, the direction of the paragraph being written,
/// and the keyboard's continuity between fields, all through the
/// framework's own `TextField`.
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
        await tester.enterText(
          find.byType(EditableText),
          'typing in ${platform.name}',
        );
        expect(creates, 0, reason: 'the editor embedded a view on $platform');
        expect(find.byType(TextField), findsOneWidget);
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
    await tester.pump();
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
    await tester.pump();
    expect(name.hasFocus, isTrue);
    expect(
      tester.testTextInput.log.map((call) => call.method),
      isNot(contains('TextInput.hide')),
    );
  });

  testWidgets('the field follows the paragraph the caret is in', (
    tester,
  ) async {
    // ADR-037's rule, moved to where it is felt: the paragraph being
    // written owns the field's direction, so a two-language note is laid
    // out around whichever paragraph the caret is in — and only that one.
    final controller = TextEditingController(text: 'سلام\nhello\nدوباره');
    addTearDown(controller.dispose);
    await pump(
      tester,
      NexTextField(controller: controller, maxLines: 5, autofocus: true),
    );
    TextField field() => tester.widget<TextField>(find.byType(TextField));
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    expect(field().textDirection, TextDirection.rtl);
    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();
    expect(field().textDirection, TextDirection.ltr);
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    expect(field().textDirection, TextDirection.rtl);
  });

  testWidgets('the field turns in place: same editor, same focus', (
    tester,
  ) async {
    // The direction moves with the caret, which changes the layout, and
    // only the layout: a field rebuilt from scratch when it turned would
    // lose the very focus and selection the turn is happening to.
    final controller = TextEditingController(text: 'سلام\nhello');
    addTearDown(controller.dispose);
    await pump(
      tester,
      NexTextField(controller: controller, maxLines: 5, autofocus: true),
    );
    final editor = find.byType(EditableText);
    final before = tester.state<EditableTextState>(editor);
    expect(before.widget.focusNode.hasFocus, isTrue);
    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
    );
    expect(tester.state<EditableTextState>(editor), same(before));
    expect(before.widget.focusNode.hasFocus, isTrue);
    expect(controller.selection.isValid, isTrue);
  });

  testWidgets("a selection being dragged keeps the anchor's side", (
    tester,
  ) async {
    // The anchor is the end a selection is *from* — the one that stays
    // put while the other is dragged. A field that followed the dragged
    // end would relayout under the finger as it crossed into a paragraph
    // written in the other language.
    final controller = TextEditingController(text: 'سلام\nhello');
    addTearDown(controller.dispose);
    await pump(tester, NexTextField(controller: controller, maxLines: 5));
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 7);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
      reason: 'the anchor is in the Persian paragraph',
    );
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
    final prose = tester.widget<TextField>(find.byType(TextField));
    expect(prose.enableSuggestions, isTrue);
    expect(prose.smartDashesType, SmartDashesType.enabled);
    expect(prose.smartQuotesType, SmartQuotesType.enabled);
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
    await tester.enterText(find.byType(EditableText), 'typed by nobody');
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
    expect(find.text('changed from Dart'), findsOneWidget);
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
    final before = tester.state<EditableTextState>(find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), 'typing');
    await tester.pump();
    expect(builds, greaterThan(1));
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(before),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 10);
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
    await tester.enterText(find.byType(EditableText), 'the text');
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
    await tester.enterText(find.byType(EditableText), 'abcdefgh');
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
    await tester.enterText(find.byType(EditableText), 'axbxc');
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

  testWidgets('the handles and lens are the framework\'s, and on', (
    tester,
  ) async {
    // 2.9.4 removed the custom magnifier bridge the native editor needed. The
    // framework's lens is the one that remains, and it is on by default — but
    // a later edit that passed `TextMagnifierConfiguration.disabled` would be
    // invisible in review, so it is stated and held here. The direction above
    // the field is what puts the handles on the ends the paragraph is drawn
    // between; `nex_text_direction_test.dart` holds that separately.
    final controller = TextEditingController(text: 'متن فارسی');
    addTearDown(controller.dispose);
    await pump(tester, NexTextField(controller: controller, maxLines: 3));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.magnifierConfiguration,
      TextMagnifier.adaptiveMagnifierConfiguration,
      reason: 'the selection lens was disabled',
    );
    expect(
      Directionality.of(tester.element(find.byType(TextField))),
      TextDirection.rtl,
      reason: 'the handles resolve against this direction',
    );
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
      tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
      'Write a note',
    );
    expect(find.text('Write a note'), findsOneWidget);
  });
}
