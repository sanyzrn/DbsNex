import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/nex_text_field.dart';

/// The Dart half of the native editor (ADR-037), driven the way Android
/// drives it: the platform-view channel answered by a fake, and the view's
/// own channel spoken to from "native" in both directions.
void main() {
  late List<MethodCall> toNative;
  late Map<String, Object?>? created;
  late int viewId;

  setUp(() {
    NexTextField.native = true;
    toNative = [];
    created = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final args = (call.arguments as Map).cast<String, Object?>();
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
      }
      return null;
    });
  });

  tearDown(() {
    NexTextField.native = false;
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
    expect(created!['text'], 'سلام Nex!');
    expect(created!['hint'], 'بنویسید');
    expect(created!['minLines'], 3);
    expect(created!['maxLines'], 0, reason: 'null maxLines grows unbounded');
    expect(created!['imeAction'], 'send');
    expect(created!['rtl'], isTrue);
    final formats = (created!['formats']! as List).cast<Map<Object?, Object?>>();
    expect(
      formats.map((f) => f['id']),
      containsAll(['bold', 'italic', 'quote', 'link', 'clear']),
    );
  });

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
}
