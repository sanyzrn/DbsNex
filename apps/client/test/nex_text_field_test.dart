import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/keyboard_dismisser.dart';
import 'package:nex_client/widgets/nex_text_field.dart';

/// The Dart half of the native editor (ADR-037), driven the way Android
/// drives it: the platform-view channel answered by a fake, and the view's
/// own channel spoken to from "native" in both directions.
void main() {
  late List<MethodCall> toNative;
  late Map<String, Object?>? created;
  late int viewId;
  late bool hybrid;
  late int createCount;

  setUp(() {
    NexTextField.native = true;
    NexTextField.flutterMagnifier = true;
    toNative = [];
    created = null;
    createCount = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        createCount++;
        final args = (call.arguments as Map).cast<String, Object?>();
        hybrid = args['hybrid'] == true;
        viewId = args['id']! as int;
        final params = args['params'] as Uint8List;
        created =
            (const StandardMessageCodec().decodeMessage(
                      ByteData.sublistView(params),
                    )
                    as Map)
                .cast<String, Object?>();
        messenger.setMockMethodCallHandler(
          MethodChannel('nex/edit_text/$viewId'),
          (call) async {
            toNative.add(call);
            return null;
          },
        );
        // Exercise real texture composition, including resizes. Returning
        // null silently selects hybrid fallback and misses editor regressions.
        return args['hybrid'] == true ? null : viewId;
      }
      if (call.method == 'resize') {
        final args = call.arguments as Map;
        return {'width': args['width'], 'height': args['height']};
      }
      return null;
    });
  });

  tearDown(() {
    NexTextField.native = false;
    NexTextField.flutterMagnifier = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Future<void> fromNative(
    WidgetTester tester,
    String method, [
    Object? arguments,
  ]) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'nex/edit_text/$viewId',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> pump(WidgetTester tester, Widget field) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: field)),
      ),
    );
    await tester.pump();
  }

  testWidgets('the editor is created with the text and the field settings', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'سلام Nex!');
    await pump(
      tester,
      NexTextField(
        controller: controller,
        minLines: 3,
        formatting: true,
        textInputAction: TextInputAction.send,
        decoration: const InputDecoration(hintText: 'بنویسید'),
      ),
    );

    expect(created, isNotNull);
    expect(
      hybrid,
      isFalse,
      reason: 'opening an editor must not force hybrid scene composition',
    );
    expect(created, isNot(contains('backgroundColor')));
    final surface = tester.widget<AndroidViewSurface>(
      find.byType(AndroidViewSurface),
    );
    expect(surface.controller.requiresViewComposition, isFalse);
    expect(created!['text'], 'سلام Nex!');
    expect(created!['hint'], 'بنویسید');
    expect(created!['minLines'], 3);
    expect(created!['maxLines'], 0, reason: 'null maxLines grows unbounded');
    expect(created!['imeAction'], 'send');
    expect(created!['rtl'], isTrue);
    final formats = (created!['formats']! as List)
        .cast<Map<Object?, Object?>>();
    expect(
      formats.map((f) => f['id']),
      containsAll(['bold', 'italic', 'quote', 'link', 'clear']),
    );
  });

  for (final brightness in Brightness.values) {
    for (final filled in [false, true]) {
      testWidgets('${brightness.name}, filled=$filled: the decoration owns '
          'the fill and the texture survives focus, resize and keyboard', (
        tester,
      ) async {
        final controller = TextEditingController(text: 'سلام\nHello!');
        addTearDown(controller.dispose);
        addTearDown(tester.view.reset);
        const fieldFill = Color(0x1A0088FF);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: brightness,
              inputDecorationTheme: const InputDecorationTheme(
                filled: true,
                fillColor: Color(0xFFE0E0E0),
              ),
            ),
            home: Scaffold(
              body: NexTextField(
                controller: controller,
                minLines: 3,
                decoration: InputDecoration(
                  filled: filled,
                  fillColor: fieldFill,
                  suffixIcon: const Icon(Icons.content_paste),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final id = viewId;
        expect(created, isNot(contains('backgroundColor')));
        final decoration = tester
            .widget<InputDecorator>(find.byType(InputDecorator))
            .decoration;
        expect(decoration.filled, filled);
        expect(decoration.fillColor, fieldFill);

        await fromNative(tester, 'focus', {'focused': true});
        await fromNative(tester, 'height', {'height': 180.0});
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        final surface = tester.widget<AndroidViewSurface>(
          find.byType(AndroidViewSurface),
        );
        expect(surface.controller.requiresViewComposition, isFalse);
        expect(viewId, id);
        expect(createCount, 1);
        expect(
          toNative.where((c) => c.method == 'update').map((c) => c.arguments),
          everyElement(isNot(contains('backgroundColor'))),
        );
        expect(controller.text, 'سلام\nHello!');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('typing in the editor reaches the controller, and is not echoed '
      'back', (tester) async {
    final controller = TextEditingController();
    final changes = <String>[];
    await pump(
      tester,
      NexTextField(controller: controller, onChanged: changes.add),
    );

    await fromNative(tester, 'changed', {
      'text': 'Hello دنیا!',
      'start': 11,
      'end': 11,
    });

    expect(controller.text, 'Hello دنیا!');
    expect(controller.selection, const TextSelection.collapsed(offset: 11));
    expect(changes, ['Hello دنیا!']);
    expect(toNative.where((c) => c.method == 'setValue'), isEmpty);

    await fromNative(tester, 'selection', {'start': 0, 'end': 5});
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    expect(toNative.where((c) => c.method == 'setValue'), isEmpty);
  });

  testWidgets('a change made in Dart is sent to the editor', (tester) async {
    final controller = TextEditingController(text: 'draft');
    await pump(tester, NexTextField(controller: controller));

    controller.text = 'rewritten by the assistant';
    await tester.pump();

    final sent = toNative.singleWhere((c) => c.method == 'setValue');
    expect((sent.arguments as Map)['text'], 'rewritten by the assistant');
  });

  testWidgets('typing and parent rebuilds keep the editor and config stable', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'سلام Nex!');
    addTearDown(controller.dispose);
    late StateSetter rebuild;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return NexTextField(controller: controller, formatting: true);
        },
      ),
    );
    final id = viewId;
    toNative.clear();
    for (final text in ['سلام Nex! one', 'سلام Nex! one two', 'سلام Nex!']) {
      await fromNative(tester, 'changed', {
        'text': text,
        'start': text.length,
        'end': text.length,
      });
      rebuild(() {});
      await tester.pump();
    }
    expect(controller.text, 'سلام Nex!');
    expect(viewId, id);
    expect(createCount, 1);
    expect(toNative.where((c) => c.method == 'setValue'), isEmpty);
    expect(toNative.where((c) => c.method == 'update'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the field takes the height the editor measured', (tester) async {
    final controller = TextEditingController();
    await pump(tester, NexTextField(controller: controller));

    await fromNative(tester, 'height', {'height': 137.0});

    final view = find.byType(PlatformViewLink);
    expect(tester.getSize(view).height, 137);
  });

  testWidgets('a format chosen on the native menu formats the selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'one two');
    final changes = <String>[];
    await pump(
      tester,
      NexTextField(
        controller: controller,
        formatting: true,
        onChanged: changes.add,
      ),
    );

    await fromNative(tester, 'format', {'id': 'bold', 'start': 4, 'end': 7});

    expect(controller.text, 'one **two**');
    expect(changes.single, 'one **two**');
    expect(
      (toNative.lastWhere((c) => c.method == 'setValue').arguments
          as Map)['text'],
      'one **two**',
    );
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'native Link ${cancel ? 'cancel' : 'save'} hands focus back after the URL input leaves',
      (tester) async {
        final controller = TextEditingController(text: 'one two');
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await pump(
          tester,
          NexTextField(
            controller: controller,
            focusNode: focus,
            formatting: true,
          ),
        );
        focus.requestFocus();
        await tester.pump();
        await fromNative(tester, 'focus', {'focused': true});
        final formatted = tester.binding.defaultBinaryMessenger
            .handlePlatformMessage(
              'nex/edit_text/$viewId',
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('format', {
                  'id': 'link',
                  'start': 4,
                  'end': 7,
                }),
              ),
              (_) {},
            );
        await tester.pumpAndSettle();
        expect(find.bySubtype<AlertDialog>(), findsOneWidget);
        // The URL input owns the keyboard now; this is the hand-off that the
        // old focus-conditional cleanup missed when the editor later closed.
        await fromNative(tester, 'focus', {'focused': false});
        toNative.clear();
        await tester.enterText(find.byType(TextField), 'https://example.com');
        final l10n = AppLocalizations.of(
          tester.element(find.bySubtype<AlertDialog>()),
        );
        await tester.tap(find.text(cancel ? l10n.cancel : l10n.save));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // Ignore focus restored at pop: the native IME needs a hand-off
        // after the outgoing URL field is actually removed.
        toNative.clear();
        await tester.pumpAndSettle();
        await formatted;
        expect(find.bySubtype<AlertDialog>(), findsNothing);
        expect(toNative.map((call) => call.method), contains('focus'));
        expect(
          controller.text,
          cancel ? 'one two' : 'one [two](https://example.com)',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Enter sends where the field sends', (tester) async {
    final controller = TextEditingController(text: 'ask this');
    final submitted = <String>[];
    await pump(
      tester,
      NexTextField(
        controller: controller,
        textInputAction: TextInputAction.send,
        onSubmitted: submitted.add,
      ),
    );

    await fromNative(tester, 'submit');

    expect(submitted, ['ask this']);
  });

  testWidgets('a private field copies through its own clipboard, and a cut '
      'takes the words out', (tester) async {
    final controller = TextEditingController(text: 'pin 4821 here');
    final copied = <String>[];
    await pump(
      tester,
      NexTextField(
        controller: controller,
        onCopy: (text) async => copied.add(text),
      ),
    );
    expect(created!['privateCopy'], isTrue);

    await fromNative(tester, 'copy', {'start': 4, 'end': 8, 'cut': false});
    expect(copied, ['4821']);
    expect(controller.text, 'pin 4821 here');

    await fromNative(tester, 'copy', {'start': 4, 'end': 9, 'cut': true});
    expect(copied, ['4821', '4821 ']);
    expect(controller.text, 'pin here');
  });

  testWidgets('focus asked for in Dart focuses the editor, and the editor '
      'losing it is told', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pump(tester, NexTextField(controller: controller, focusNode: focus));

    focus.requestFocus();
    await tester.pump();
    expect(toNative.map((c) => c.method), contains('focus'));

    await fromNative(tester, 'focus', {'focused': true});
    toNative.clear();
    focus.unfocus();
    await tester.pump();
    expect(toNative.map((c) => c.method), contains('unfocus'));
  });

  testWidgets('a label inside the empty field keeps the hint off the editor', (
    tester,
  ) async {
    final controller = TextEditingController();
    await pump(
      tester,
      NexTextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Bio', hintText: 'More'),
      ),
    );
    expect(created!['hint'], isNull);

    await fromNative(tester, 'changed', {'text': 'x', 'start': 1, 'end': 1});
    final update = toNative.lastWhere((c) => c.method == 'update');
    expect((update.arguments as Map)['hint'], 'More');
  });

  testWidgets('off Android it is a Flutter field in the text\'s direction', (
    tester,
  ) async {
    NexTextField.native = false;
    final controller = TextEditingController(text: 'سلام');
    await pump(tester, NexTextField(controller: controller, maxLines: 4));

    expect(find.byType(PlatformViewLink), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textDirection, TextDirection.rtl);
    expect(field.maxLines, 4);
  });

  testWidgets(
    'the native child keeps focus while selecting near the decorated edge',
    (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.reset);
      addTearDown(tester.view.resetViewInsets);
      final controller = TextEditingController(text: 'سلام\nHello');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => NexKeyboardDismisser(child: child!),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: NexTextField(
                  controller: controller,
                  focusNode: focus,
                  minLines: 3,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Focus.of(tester.element(find.byType(AndroidViewSurface))).requestFocus();
      await tester.pump();
      await fromNative(tester, 'focus', {'focused': true});
      final bounds = tester.getRect(find.byType(InputDecorator));
      toNative.clear();
      for (final point in [
        Offset(bounds.left - 6, bounds.center.dy),
        Offset(bounds.right + 6, bounds.center.dy),
        Offset(bounds.center.dx, bounds.bottom + 18),
      ]) {
        await tester.tapAt(point);
        await tester.pump();
        expect(focus.hasFocus, isTrue);
      }
      expect(toNative.map((c) => c.method), isNot(contains('unfocus')));
      await tester.tapAt(Offset(bounds.center.dx, bounds.bottom + 54));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(toNative.map((c) => c.method), contains('unfocus'));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a tap inside the editor with the keyboard up keeps it focused, '
      'in the app as it runs, under the keyboard dismisser', (tester) async {
    // 1.91.0's keyboard rule dropped focus on every touch in the app, and a
    // tap in the capture box or the note editor closed the keyboard. Any
    // field built on NexTextField goes through this path.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    final controller = TextEditingController(text: 'یادداشت');
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => NexKeyboardDismisser(child: child!),
        home: Scaffold(
          body: Center(
            child: NexTextField(
              controller: controller,
              focusNode: focus,
              minLines: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    await fromNative(tester, 'focus', {'focused': true});
    toNative.clear();

    final press = await tester.startGesture(
      tester.getCenter(find.byType(PlatformViewLink)),
    );
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await press.up();
    await tester.pumpAndSettle();

    expect(focus.hasFocus, isTrue);
    expect(toNative.map((c) => c.method), isNot(contains('unfocus')));
  });

  Map<String, Object?> loupe({bool show = true}) => {
    'show': show,
    'x': 100.0,
    'caretX': 96.0,
    'top': 4.0,
    'bottom': 28.0,
    'left': 12.0,
    'right': 220.0,
    'width': 240.0,
    'height': 100.0,
  };

  testWidgets(
    'native caret geometry drives the stock Flutter loupe without editing text',
    (tester) async {
      final controller = TextEditingController(
        text: 'سلام Nex!\nEnglish line.',
      );
      addTearDown(controller.dispose);
      await pump(
        tester,
        SizedBox(
          width: 260,
          child: NexTextField(controller: controller, minLines: 4),
        ),
      );
      expect(created!['flutterMagnifier'], isTrue);
      await fromNative(tester, 'focus', {'focused': true});
      toNative.clear();
      final original = controller.value;
      final origin = tester.getTopLeft(find.byType(PlatformViewLink));
      await fromNative(tester, 'magnifier', loupe());
      expect(find.byType(TextMagnifier), findsOneWidget);
      final first = tester.widget<TextMagnifier>(find.byType(TextMagnifier));
      expect(
        first.magnifierInfo.value.caretRect.topLeft,
        origin + const Offset(96, 4),
      );
      expect(
        first.magnifierInfo.value.globalGesturePosition,
        origin + const Offset(100, 16),
      );
      final notifier = first.magnifierInfo;
      await fromNative(tester, 'selection', {'start': 2, 'end': 7});
      await fromNative(tester, 'magnifier', {
        ...loupe(),
        'x': 135.0,
        'caretX': 130.0,
      });
      expect(
        tester.widget<TextMagnifier>(find.byType(TextMagnifier)).magnifierInfo,
        same(notifier),
      );
      expect(controller.text, original.text);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 7),
      );
      expect(toNative.where((c) => c.method == 'setValue'), isEmpty);
      expect(createCount, 1);
      expect(hybrid, isFalse);
      await fromNative(tester, 'magnifier', loupe(show: false));
      await tester.pumpAndSettle();
      expect(find.byType(TextMagnifier), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the native loupe closes on typing, focus loss and invalid geometry',
    (tester) async {
      final controller = TextEditingController(text: 'متن قابل انتخاب');
      addTearDown(controller.dispose);
      await pump(tester, NexTextField(controller: controller, minLines: 4));
      Future<void> show() async {
        await fromNative(tester, 'focus', {'focused': true});
        await fromNative(tester, 'magnifier', loupe());
        expect(find.byType(TextMagnifier), findsOneWidget);
      }

      await show();
      await fromNative(tester, 'changed', {
        'text': 'یک ویرایش',
        'start': 3,
        'end': 3,
      });
      expect(find.byType(TextMagnifier), findsNothing);
      await show();
      await fromNative(tester, 'focus', {'focused': false});
      expect(find.byType(TextMagnifier), findsNothing);
      await fromNative(tester, 'magnifier', loupe());
      expect(find.byType(TextMagnifier), findsNothing);
      for (final invalid in [
        {...loupe(), 'x': double.nan},
        {...loupe(), 'height': 0},
        {...loupe(), 'bottom': -4},
        {...loupe(), 'left': 1000},
      ]) {
        await show();
        await fromNative(tester, 'magnifier', invalid);
        expect(find.byType(TextMagnifier), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the loupe leaves with its route, app pause, keyboard resize or field',
    (tester) async {
      addTearDown(tester.view.resetViewInsets);
      final controller = TextEditingController(text: 'سلام\nHello');
      addTearDown(controller.dispose);
      await pump(tester, NexTextField(controller: controller, minLines: 4));
      await fromNative(tester, 'focus', {'focused': true});
      await fromNative(tester, 'magnifier', loupe());
      final navigator = Navigator.of(tester.element(find.byType(NexTextField)));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Next route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextMagnifier), findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      await fromNative(tester, 'focus', {'focused': true});
      await fromNative(tester, 'magnifier', loupe());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(TextMagnifier), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await fromNative(tester, 'magnifier', loupe());
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pumpAndSettle();
      expect(find.byType(TextMagnifier), findsNothing);
      tester.view.resetViewInsets();
      await tester.pump();
      await fromNative(tester, 'magnifier', loupe());
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(find.byType(TextMagnifier), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the experimental native loupe can be disabled independently', (
    tester,
  ) async {
    NexTextField.flutterMagnifier = false;
    final controller = TextEditingController(text: 'متن');
    addTearDown(controller.dispose);
    await pump(tester, NexTextField(controller: controller, minLines: 4));
    expect(created!['flutterMagnifier'], isFalse);
    await fromNative(tester, 'focus', {'focused': true});
    await fromNative(tester, 'magnifier', loupe());
    expect(find.byType(TextMagnifier), findsNothing);
    expect(hybrid, isFalse);
  });
}
