import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/nex_field_chrome.dart';
import 'package:nex_client/widgets/nex_paragraph_editor.dart';

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
    expect(find.text('یادداشت'), findsNothing);
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

  testWidgets('a selection offers the format bar and bold writes markdown', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'سلام دنیا');
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

    await tester.tap(find.byType(NexParagraphEditor));
    await tester.pumpAndSettle();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pumpAndSettle();
    expect(find.byType(NexSelectionFormatBar), findsOneWidget);

    await tester.tap(find.text('Bold'));
    await tester.pumpAndSettle();
    expect(controller.text, '**سلام** دنیا');
    // The menu closes after a command, the way a platform menu does.
    expect(find.byType(NexSelectionFormatBar), findsNothing);
  });
}
