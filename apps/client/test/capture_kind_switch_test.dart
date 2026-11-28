import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_client/widgets/nex_dialog.dart';
import 'package:nex_client/widgets/nex_text_field.dart';
import 'package:nex_client/widgets/nex_paragraph_editor.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';
import 'support/text_input.dart';

void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_capture_kinds_');
  });

  tearDown(() async {
    await harness.dispose();
  });

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

  testWidgets('capture kinds keep the text, caret and keyboard', (
    tester,
  ) async {
    await open(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(CaptureSheet)));
    final row = find.byKey(const ValueKey('capture-input-row'));
    final field = find.byType(NexTextField);
    NexTextField input() => tester.widget<NexTextField>(field);

    await enterNexText(tester, nexInputs(), 'سلام!\nHello.');
    await tester.pumpAndSettle();
    final controller = input().controller;
    const selection = TextSelection.collapsed(offset: 8);
    controller.selection = selection;
    await tester.pumpAndSettle();
    final layout = tester.getRect(row);

    for (final label in [
      l10n.code,
      l10n.captureKindNote,
      l10n.checklist,
      l10n.link,
      l10n.captureKindNote,
    ]) {
      tester.testTextInput.log.clear();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(input().controller, same(controller));
      expect(controller.text, 'سلام!\nHello.');
      expect(controller.selection, selection, reason: label);
      expect(input().focusNode!.hasFocus, isTrue, reason: label);
      expect(
        tester.testTextInput.log.map((call) => call.method),
        isNot(contains('TextInput.hide')),
        reason: label,
      );
      final now = tester.getRect(row);
      expect((now.top - layout.top).abs(), lessThanOrEqualTo(48));
      expect(now.bottom, lessThanOrEqualTo(500));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Code box is a code field, and stops being one', (
    tester,
  ) async {
    await open(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(CaptureSheet)));
    TextField widget() => tester.widget<TextField>(find.byType(TextField));
    NexTextField field() =>
        tester.widget<NexTextField>(find.byType(NexTextField));
    bool code() => widget().inputFormatters != null;

    expect(find.byType(NexParagraphEditor), findsOneWidget);

    await tester.tap(find.text(l10n.code));
    await tester.pumpAndSettle();
    expect(
      code(),
      isTrue,
      reason: 'the editor pairs and indents only when told it is code',
    );
    expect(field().monospace, isTrue);
    expect(field().textDirection, TextDirection.ltr);

    await tester.tap(find.text(l10n.captureKindNote));
    await tester.pumpAndSettle();
    expect(find.byType(NexParagraphEditor), findsOneWidget);
    expect(field().textDirection, isNull);
  });
}
