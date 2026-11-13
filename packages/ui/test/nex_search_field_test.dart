import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  Widget host(Widget field, {TextDirection app = TextDirection.ltr}) =>
      MaterialApp(
        theme: nexSoftLightTheme(),
        home: Directionality(
          textDirection: app,
          child: Scaffold(body: Center(child: field)),
        ),
      );

  EditableText editable(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText));

  testWidgets('clear appears with text and resets the list at once', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];
    await tester.pumpWidget(
      host(
        NexSearchField(
          controller: controller,
          hintText: 'Search',
          onChanged: changes.add,
        ),
      ),
    );
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.enterText(find.byType(NexSearchField), 'milk');
    await tester.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byTooltip('Clear text'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(changes.last, '', reason: 'a filtered list resets now');
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('without clear, there is no button', (tester) async {
    final controller = TextEditingController(text: 'x');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(NexSearchField(controller: controller, clearable: false)),
    );
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('direction follows the script typed', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(NexSearchField(controller: controller)));
    await tester.enterText(find.byType(NexSearchField), 'کتاب');
    await tester.pump();
    expect(editable(tester).textDirection, TextDirection.rtl);
    await tester.enterText(find.byType(NexSearchField), 'book');
    await tester.pump();
    expect(editable(tester).textDirection, TextDirection.ltr);
  });

  testWidgets('a fixed direction stays fixed in a right-to-left app', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        NexSearchField(
          controller: controller,
          textDirection: TextDirection.ltr,
        ),
        app: TextDirection.rtl,
      ),
    );
    await tester.enterText(find.byType(NexSearchField), 'مدل');
    await tester.pump();
    expect(editable(tester).textDirection, TextDirection.ltr);
  });

  testWidgets('private turns off suggestions and learning', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(NexSearchField(controller: controller, private: true)),
    );
    final field = editable(tester);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
  });

  testWidgets('on a page it takes the theme; on a surface, only focus', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(NexSearchField(controller: controller)));
    var decoration = tester
        .widget<TextField>(find.byType(TextField))
        .decoration!;
    expect(decoration.enabledBorder, isNull, reason: 'from the theme');
    expect(decoration.filled, isNull);

    await tester.pumpWidget(
      host(
        NexSearchField(
          controller: controller,
          ground: NexSearchFieldGround.surface,
        ),
      ),
    );
    decoration = tester.widget<TextField>(find.byType(TextField)).decoration!;
    expect(decoration.filled, isFalse);
    expect(
      (decoration.enabledBorder! as OutlineInputBorder).borderSide,
      BorderSide.none,
    );
    expect(
      (decoration.focusedBorder! as OutlineInputBorder).borderSide.width,
      nexFocusRingWidth,
    );
  });

  testWidgets('the key reaches the text field for finders', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        NexSearchField(
          controller: controller,
          fieldKey: const ValueKey('the-search'),
        ),
      ),
    );
    expect(
      tester.widget(find.byKey(const ValueKey('the-search'))),
      isA<TextField>(),
    );
  });
}
