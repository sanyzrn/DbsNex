import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_client/widgets/nex_dialog.dart';
import 'package:nex_client/widgets/nex_text_field.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// 2.9.0, step 5: the capture box's four kinds are one editor.
///
/// Code used to be the one kind that swapped editors — Android's for
/// Flutter's — and the swap took the keyboard with it, collapsing the
/// sheet's bottom inset and moving the panel. These tests hold the box to
/// one editor for every kind: the same editor element, its words, its
/// place, and its code settings — which, the editor being the framework's
/// own on every platform now, are the field's own.
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

  testWidgets('every kind keeps the one editor, the text and its place', (
    tester,
  ) async {
    await open(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(CaptureSheet)));
    final row = find.byKey(const ValueKey('capture-input-row'));
    final field = find.byType(NexTextField);

    await tester.enterText(
      find.descendant(of: field, matching: find.byType(EditableText)),
      'hello',
    );
    await tester.pumpAndSettle();
    final resting = tester.getRect(row);
    final editor = tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
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
        tester.state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        ),
        same(editor),
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
        editor.widget.focusNode.hasFocus,
        isTrue,
        reason:
            'nothing gave the editor up while the kind changed — that is '
            'what dropped the keyboard',
      );
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

    expect(code(), isFalse);

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
    expect(code(), isFalse);
    expect(field().textDirection, isNull);
  });
}
