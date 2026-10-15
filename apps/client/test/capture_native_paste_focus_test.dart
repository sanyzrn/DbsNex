import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_client/widgets/nex_text_field.dart';

import 'support/nex_harness.dart';

void main() {
  for (final kind in [
    CaptureKind.note,
    CaptureKind.checklist,
    CaptureKind.link,
  ]) {
    testWidgets('${kind.name}: paste retains the native child focus', (
      tester,
    ) async {
      final h = await NexTestHarness.create();
      NexTextField.native = true;
      final messenger = tester.binding.defaultBinaryMessenger;
      final calls = <String>[];
      var viewId = -1;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          viewId = (call.arguments as Map)['id'] as int;
          messenger.setMockMethodCallHandler(
            MethodChannel('nex/edit_text/$viewId'),
            (call) async {
              calls.add(call.method);
              return null;
            },
          );
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? {'text': 'https://example.com'}
            : null,
      );
      addTearDown(() async {
        NexTextField.native = false;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        if (viewId >= 0) {
          messenger.setMockMethodCallHandler(
            MethodChannel('nex/edit_text/$viewId'),
            null,
          );
        }
        await h.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CaptureSheet(
              services: h.services,
              preferences: h.preferences,
              initialKind: kind,
              onCamera: () {},
              onGallery: () {},
              onFile: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surface = find.byType(AndroidViewSurface);
      expect(surface, findsOneWidget);
      final nativeFocus = Focus.of(tester.element(surface));
      nativeFocus.requestFocus();
      await tester.pump();
      await messenger.handlePlatformMessage(
        'nex/edit_text/$viewId',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('focus', {'focused': true}),
        ),
        (_) {},
      );
      await tester.pump();
      final parentFocus = tester
          .widget<NexTextField>(find.byType(NexTextField))
          .focusNode!;
      expect(parentFocus.hasFocus, isTrue);
      expect(parentFocus.hasPrimaryFocus, isFalse);
      calls.clear();
      await tester.tap(find.byKey(const ValueKey('capture-paste')));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(nativeFocus));
      expect(
        calls.where((call) => call == 'focus' || call == 'unfocus'),
        isEmpty,
      );
      expect(
        tester.widget<NexTextField>(find.byType(NexTextField)).controller.text,
        'https://example.com',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
