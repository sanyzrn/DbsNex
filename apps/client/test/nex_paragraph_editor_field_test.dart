import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/nex_paragraph_editor.dart';
import 'package:nex_client/widgets/nex_text_field.dart';
import 'package:super_editor/super_editor.dart';

import 'support/text_input.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 360,
        height: 320,
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('the field draws its hint until there is text', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _host(
        NexParagraphEditor(
          controller: controller,
          minLines: 2,
          decoration: const InputDecoration(hintText: 'یادداشت'),
        ),
      ),
    );
    expect(find.text('یادداشت'), findsOneWidget);
    await tester.pumpWidget(
      _host(
        NexParagraphEditor(
          controller: controller..text = 'سلام',
          minLines: 2,
          decoration: const InputDecoration(hintText: 'یادداشت'),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<InputDecorator>(find.byType(InputDecorator)).isEmpty,
      isFalse,
    );
  });

  testWidgets('the box grows with the lines and stops at maxLines', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _host(
        NexParagraphEditor(controller: controller, minLines: 1, maxLines: 4),
      ),
    );
    final one = tester.getSize(find.byType(NexParagraphEditor)).height;

    await tester.pumpWidget(
      _host(
        NexParagraphEditor(controller: controller..text = 'a\nb', minLines: 1),
      ),
    );
    await tester.pump();
    final two = tester.getSize(find.byType(NexParagraphEditor)).height;
    expect(two, greaterThan(one));

    await tester.pumpWidget(
      _host(
        NexParagraphEditor(
          controller: controller..text = List.filled(9, 'x').join('\n'),
          minLines: 1,
          maxLines: 2,
        ),
      ),
    );
    await tester.pump();
    final capped = tester.getSize(find.byType(NexParagraphEditor)).height;
    expect(capped, two);

    await tester.pumpWidget(
      _host(
        NexParagraphEditor(
          controller: controller..text = List.filled(9, 'x').join('\n'),
          minLines: 1,
        ),
      ),
    );
    await tester.pump();
    final unbounded = tester.getSize(find.byType(NexParagraphEditor)).height;
    expect(unbounded, greaterThan(capped));
  });

  testWidgets('a Persian word opens one toolbar and bold writes markdown', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'سلام دنیا');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        NexParagraphEditor(
          controller: controller,
          minLines: 2,
          formatting: true,
          autofocus: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editor = find.byType(SuperEditor);
    final state = tester.state(editor);
    tester.testTextInput.log.clear();
    await selectNexWord(tester, 2);
    expect(controller.selection.textInside(controller.text), 'سلام');
    expect(find.byKey(DocumentKeys.mobileToolbar), findsOneWidget);
    expect(tester.state(editor), same(state));
    expect(
      tester.testTextInput.log.map((call) => call.method),
      isNot(contains('TextInput.hide')),
    );

    await chooseNexFormat(tester, 'Bold');
    expect(controller.text, '**سلام** دنیا');
    expect(find.byKey(DocumentKeys.mobileToolbar), findsNothing);
  });

  testWidgets(
    'multiline fields scroll inside a form and measure wrapped text',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final field = nexInputs(hintText: 'Body');
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 35),
                NexTextField(
                  controller: controller,
                  maxLines: 4,
                  maxLength: 180,
                  decoration: const InputDecoration(
                    hintText: 'Body',
                    labelText: 'Label',
                    helperText: 'Helper',
                    prefixIcon: Icon(Icons.edit),
                  ),
                ),
                const SizedBox(height: 400),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final height = tester.getSize(field).height;
      final text = 'سلام دنیا!\n${List.filled(14, 'English').join(' ')}';
      await enterNexText(tester, field, text);
      await tester.pumpAndSettle();
      expect(controller.text, text);
      expect(tester.getSize(field).height, greaterThan(height * 1.3));
      expect(find.text('Label'), findsOneWidget);
      expect(find.text('Helper'), findsOneWidget);
      expect(find.text('${text.length}/180'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
      final paragraphs = find.byType(ParagraphComponent).evaluate();
      expect(
        [
          for (final paragraph in paragraphs)
            (paragraph.widget as ParagraphComponent).viewModel.textDirection,
        ],
        [TextDirection.rtl, TextDirection.ltr],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('character limits count graphemes on the IME path', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final field = nexInputs(hintText: 'Body');
    await tester.pumpWidget(
      _host(
        NexTextField(
          controller: controller,
          maxLines: 3,
          maxLength: 3,
          decoration: const InputDecoration(hintText: 'Body'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await enterNexText(tester, field, 'آ👩‍💻بج');
    await tester.pumpAndSettle();
    expect(controller.text, 'آ👩‍💻ب');
    expect(find.text('3/3'), findsOneWidget);
  });
}
