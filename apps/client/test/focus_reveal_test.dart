import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/widgets/focus_reveal.dart';

/// The field being typed in stays above the keyboard.
///
/// 2.9.0, step 4: a six-line body field in Prompt Studio was half under the
/// keyboard, because only the caret was brought into view. These tests use a
/// field of the same height on the same kind of scrolled page, and check the
/// box — not the caret — against the top of the keyboard.
/// Focuses a field the way the platform's "next" does, without a tap.
void _focusOf(WidgetTester tester, Finder field) {
  tester
      .widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      )
      .focusNode
      .requestFocus();
}

void main() {
  Widget app({required Widget home}) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    // The app installs it here: above the Navigator, so dialogs and sheets
    // are covered by the same rule.
    builder: (context, child) => NexFocusReveal(child: child!),
    home: home,
  );

  Widget form({bool rtl = false, List<TextEditingController>? controllers}) {
    final fields =
        controllers ?? [for (var i = 0; i < 6; i++) TextEditingController()];
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: const Text('Prompt')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < fields.length - 1; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  key: ValueKey('field-$i'),
                  controller: fields[i],
                  decoration: InputDecoration(labelText: 'Field $i'),
                ),
              ),
            // The tall one, as Prompt Studio's body field is.
            TextField(
              key: const ValueKey('field-last'),
              controller: fields.last,
              minLines: 6,
              maxLines: 16,
              decoration: const InputDecoration(labelText: 'Body'),
            ),
          ],
        ),
      ),
    );
  }

  void openKeyboard(WidgetTester tester, {double logical = 320}) {
    tester.view.viewInsets = FakeViewPadding(
      bottom: logical * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
  }

  double keyboardTop(WidgetTester tester, {double logical = 320}) {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    return size.height - logical;
  }

  testWidgets('the keyboard opens after the tap and the field comes above it', (
    tester,
  ) async {
    final controllers = [for (var i = 0; i < 6; i++) TextEditingController()];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    await tester.pumpWidget(app(home: form(controllers: controllers)));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('field-last'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pump();

    openKeyboard(tester);
    await tester.pumpAndSettle();

    final rect = tester.getRect(field);
    expect(
      rect.bottom,
      lessThanOrEqualTo(keyboardTop(tester) + 0.5),
      reason:
          'the whole field, not just the caret, has to be above the '
          'keyboard — it was ${rect.top}..${rect.bottom}',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('focus while the keyboard is already up is revealed too', (
    tester,
  ) async {
    final controllers = [for (var i = 0; i < 6; i++) TextEditingController()];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    await tester.pumpWidget(app(home: form(controllers: controllers)));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('field-last'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    // Taken while the field is still built: the shrunken list will recycle it
    // until the reveal brings it back, which is the thing under test.
    final node = tester
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .focusNode;
    openKeyboard(tester);
    await tester.pumpAndSettle();

    // The platform has "next field" too: focus moves, no new tap on the page.
    node.requestFocus();
    await tester.pumpAndSettle();

    expect(
      tester.getRect(field).bottom,
      lessThanOrEqualTo(keyboardTop(tester) + 0.5),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a closed keyboard moves nothing', (tester) async {
    final controllers = [for (var i = 0; i < 6; i++) TextEditingController()];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    await tester.pumpWidget(app(home: form(controllers: controllers)));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('field-last'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    final before = tester.getRect(field);
    _focusOf(tester, field);
    await tester.pumpAndSettle();
    expect(tester.getRect(field), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the rule reaches a dialog field', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    content: SizedBox(
                      height: 400,
                      child: Column(
                        children: [
                          const Spacer(),
                          TextField(
                            key: const ValueKey('dialog-field'),
                            controller: controller,
                            minLines: 4,
                            maxLines: 8,
                          ),
                        ],
                      ),
                    ),
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
    final field = find.byKey(const ValueKey('dialog-field'));
    await tester.tap(field);
    await tester.pump();
    openKeyboard(tester);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(field).bottom,
      lessThanOrEqualTo(keyboardTop(tester) + 0.5),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('right to left keeps the same rule', (tester) async {
    final controllers = [for (var i = 0; i < 6; i++) TextEditingController()];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    await tester.pumpWidget(
      app(home: form(rtl: true, controllers: controllers)),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('field-last'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pump();
    openKeyboard(tester);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(field).bottom,
      lessThanOrEqualTo(keyboardTop(tester) + 0.5),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tall field inside a sheet is lifted whole', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => nexShowSheet<void>(
                  context: context,
                  builder: (context) => SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 240),
                        TextField(
                          key: const ValueKey('sheet-field'),
                          controller: controller,
                          minLines: 6,
                          maxLines: 12,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
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
    final field = find.byKey(const ValueKey('sheet-field'));
    await tester.tap(field);
    await tester.pump();
    openKeyboard(tester);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(field).bottom,
      lessThanOrEqualTo(keyboardTop(tester) + 0.5),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a short window keeps the field visible too', (tester) async {
    tester.view.physicalSize = const Size(400, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controllers = [for (var i = 0; i < 4; i++) TextEditingController()];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    await tester.pumpWidget(app(home: form(controllers: controllers)));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('field-last'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pump();
    openKeyboard(tester, logical: 240);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(field).bottom,
      lessThanOrEqualTo(keyboardTop(tester, logical: 240) + 0.5),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the app\'s own multi-line editor lifts its whole frame', (
    tester,
  ) async {
    // The field's frame — border, label, counter — is drawn by an
    // InputDecorator around the editor, and the editor's own caret-scroll
    // only promises the caret. The frame is what has to clear the keyboard,
    // which is the half-covered field the report describes.
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        home: Scaffold(
          body: ListView(
            children: [
              const SizedBox(height: 500),
              NexTextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Body'),
              ),
              const SizedBox(height: 600),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byType(NexTextField);
    await tester.tap(field);
    await tester.pump();
    openKeyboard(tester, logical: 300);
    await tester.pumpAndSettle();

    final frame = tester.getRect(find.byType(InputDecorator));
    expect(
      frame.bottom,
      lessThanOrEqualTo(keyboardTop(tester, logical: 300) + 0.5),
      reason:
          'the whole frame has to clear the keyboard, not only the caret — '
          'frame ${frame.top}..${frame.bottom}',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('remove animations is still correct', (tester) async {
    final controllers = [for (var i = 0; i < 6; i++) TextEditingController()];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(app(home: form(controllers: controllers)));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('field-last'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pump();
    openKeyboard(tester);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(field).bottom,
      lessThanOrEqualTo(keyboardTop(tester) + 0.5),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
