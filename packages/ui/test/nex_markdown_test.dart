import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

const _persian = '''
# سرتیتر فارسی

یک پاراگراف فارسی با یک کلمهٔ English داخلش.

- مورد اول
- مورد دوم
''';

const _english = '''
# An English heading

A paragraph, and a list:

- first
- second
''';

const _width = 400.0;

Future<void> pumpMarkdown(
  WidgetTester tester,
  String text, {
  required TextDirection ambient,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: ambient,
        child: Scaffold(
          body: SizedBox(
            width: _width,
            child: SingleChildScrollView(child: NexMarkdown(text)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The direction the rendered document actually got, read from inside the
/// renderer rather than from what we passed in.
TextDirection renderedDirection(WidgetTester tester) =>
    Directionality.of(tester.element(find.byType(MarkdownBody)));

void main() {
  group('direction comes from the document, not the interface', () {
    testWidgets('a Persian document is right-to-left in an English app', (
      tester,
    ) async {
      // The whole reason this widget exists. `flutter_markdown_plus` follows
      // the ambient Directionality, and the ambient direction here is the
      // interface language — which is not what decides in this app.
      await pumpMarkdown(tester, _persian, ambient: TextDirection.ltr);
      expect(renderedDirection(tester), TextDirection.rtl);
    });

    testWidgets('an English document is left-to-right in a Persian app', (
      tester,
    ) async {
      await pumpMarkdown(tester, _english, ambient: TextDirection.rtl);
      expect(renderedDirection(tester), TextDirection.ltr);
    });

    testWidgets('text with no direction of its own keeps the ambient one', (
      tester,
    ) async {
      await pumpMarkdown(
        tester,
        '# 12:30\n\n- 1\n- 2',
        ambient: TextDirection.rtl,
      );
      expect(renderedDirection(tester), TextDirection.rtl);
    });

    testWidgets('a Persian list puts its bullets on the right', (tester) async {
      // Direction that only reaches the text and not the layout is the exact
      // half-fix this is guarding against, so the bullet's own position is
      // asserted rather than the Directionality alone.
      await pumpMarkdown(tester, _persian, ambient: TextDirection.ltr);
      final bullet = find.text('•').first;
      expect(bullet, findsOneWidget);
      final centre = tester.getCenter(bullet).dx;
      expect(
        centre,
        greaterThan(_width / 2),
        reason: 'the bullet is on the left, so the list is laid out LTR',
      );
    });
  });

  group('nexLooksLikeMarkdown', () {
    test('says yes to structure worth rendering', () {
      expect(nexLooksLikeMarkdown('# Heading'), isTrue);
      expect(nexLooksLikeMarkdown('- one\n- two'), isTrue);
      expect(nexLooksLikeMarkdown('1. one\n2. two'), isTrue);
      expect(nexLooksLikeMarkdown('some **bold** text'), isTrue);
      expect(nexLooksLikeMarkdown('run `flutter test` first'), isTrue);
      expect(nexLooksLikeMarkdown('```dart\nfinal x = 1;\n```'), isTrue);
      expect(nexLooksLikeMarkdown('> quoted'), isTrue);
      expect(nexLooksLikeMarkdown('| a | b |\n|---|---|'), isTrue);
      expect(nexLooksLikeMarkdown('see [the docs](https://x.dev)'), isTrue);
      expect(nexLooksLikeMarkdown('- مورد اول\n- مورد دوم'), isTrue);
    });

    test('says no to ordinary prose', () {
      expect(nexLooksLikeMarkdown(''), isFalse);
      expect(nexLooksLikeMarkdown('   '), isFalse);
      expect(nexLooksLikeMarkdown('Just a sentence.'), isFalse);
      // The case that would cost something if it were wrong: an asterisk or an
      // underscore loose in prose is not markup, and rendering it as markup
      // would delete a character the user typed.
      expect(nexLooksLikeMarkdown('2 * 3 = 6'), isFalse);
      expect(nexLooksLikeMarkdown('the file is my_notes.txt'), isFalse);
      expect(nexLooksLikeMarkdown('یک جملهٔ فارسی ساده.'), isFalse);
      // A dash used as punctuation mid-line, not as a list marker.
      expect(nexLooksLikeMarkdown('سلام - حالت خوبه؟'), isFalse);
    });
  });
}
