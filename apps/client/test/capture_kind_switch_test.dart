import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/widgets/capture_sheet.dart';

import 'support/nex_harness.dart';

/// 2.9.0, step 5: the capture box's four kinds are one editor.
///
/// On Android, Code used to be the one kind that swapped Android's editor for
/// Flutter's. Entering it destroyed the platform view — taking the keyboard
/// with it, collapsing the sheet's bottom inset and moving the panel — and
/// leaving it built a second view and asked for the keyboard again. These
/// tests hold the box to one editor for every kind, and to the code settings
/// that editor needs.
void main() {
  late NexTestHarness harness;
  late int creates;
  late Map<String, Object?>? config;
  late int viewId;
  final toNative = <MethodCall>[];

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_capture_kinds_');
    NexTextField.native = true;
    creates = 0;
    config = null;
    viewId = 0;
    toNative.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        creates++;
        final args = (call.arguments as Map).cast<String, Object?>();
        viewId = args['id']! as int;
        config = (const StandardMessageCodec().decodeMessage(
          ByteData.sublistView(args['params']! as Uint8List),
        ) as Map).cast<String, Object?>();
        messenger.setMockMethodCallHandler(
          MethodChannel('nex/edit_text/$viewId'),
          (call) async {
            toNative.add(call);
            if (call.method == 'update') {
              config = (call.arguments as Map).cast<String, Object?>();
            }
            return null;
          },
        );
        return viewId;
      }
      if (call.method == 'resize') {
        final args = call.arguments as Map;
        return {'width': args['width'], 'height': args['height']};
      }
      return null;
    });
  });

  tearDown(() async {
    NexTextField.native = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
    await harness.dispose();
  });

  /// Words typed in the Android editor arrive from it, not from Flutter.
  Future<void> typed(WidgetTester tester, String text) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'nex/edit_text/$viewId',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('changed', {
          'text': text,
          'start': text.length,
          'end': text.length,
        }),
      ),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => nexShowSheet<void>(
                  context: context,
                  builder: (_) => CaptureSheet(
                    services: harness.services,
                    preferences: harness.preferences,
                    onCamera: () {},
                    onGallery: () {},
                    onFile: () {},
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The keyboard is up for the whole round trip.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
  }

  testWidgets('every kind keeps the one editor, the text and its place', (
    tester,
  ) async {
    await open(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(CaptureSheet)));
    final row = find.byKey(const ValueKey('capture-input-row'));
    expect(creates, 1);

    await typed(tester, 'hello');
    final resting = tester.getRect(row);
    final field = find.byType(NexTextField);
    expect(tester.widget<NexTextField>(field).controller.text, 'hello');

    for (final label in [
      l10n.code,
      l10n.captureKindNote,
      l10n.checklist,
      l10n.link,
      l10n.captureKindNote,
    ]) {
      final before = tester.getRect(row);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(
        creates,
        1,
        reason:
            'switching to "$label" must not swap the editor out — that is '
            'what dropped the keyboard and moved the sheet',
      );
      expect(
        tester.widget<NexTextField>(field).controller.text,
        'hello',
        reason: 'the words are the person\'s, whatever the kind is',
      );
      final now = tester.getRect(row);
      expect(
        now.height,
        resting.height,
        reason: 'the box keeps its height, whatever the kind is',
      );
      // Only the panel's own content changes (a hint line under the box, the
      // code tools above it), never the keyboard's height: the box must not
      // drop or leap when the kind does.
      expect(
        (now.top - before.top).abs(),
        lessThanOrEqualTo(48),
        reason:
            'switching to "$label" moved the box from ${before.top} to '
            '${now.top}',
      );
      if (label == l10n.code) {
        // The code tools sit above the row, so the words being typed keep
        // their place exactly.
        expect(now.top, before.top);
      }
      expect(
        now.bottom,
        lessThanOrEqualTo(
          tester.view.physicalSize.height / tester.view.devicePixelRatio - 300,
        ),
        reason: 'the box is above the keyboard the whole time',
      );
      expect(
        toNative.where((call) => call.method == 'unfocus'),
        isEmpty,
        reason:
            'nothing told the editor to give up the keyboard while the kind '
            'changed',
      );
      expect(FocusManager.instance.primaryFocus, isNotNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Code box tells the Android editor the words are code', (
    tester,
  ) async {
    await open(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(CaptureSheet)));
    expect(config!['code'], isFalse);

    await tester.tap(find.text(l10n.code));
    await tester.pumpAndSettle();
    expect(
      config!['code'],
      isTrue,
      reason: 'the native editor pairs and indents only when told it is code',
    );
    expect(config!['monospace'], isTrue);
    expect(config!['textDirection'], TextDirection.ltr.name);

    await tester.tap(find.text(l10n.captureKindNote));
    await tester.pumpAndSettle();
    expect(config!['code'], isFalse);
    expect(creates, 1);
  });
}
