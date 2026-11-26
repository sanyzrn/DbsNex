import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// Nex 2.9.1: every Markdown block reads in the direction its own words are
/// mostly written in.
///
/// The defect these cover: the renderer used to take one direction for the
/// whole document from its first strong character, so a Persian document that
/// opened with an English word — a product name, a URL, a code term — was laid
/// out left to right from its first heading to its last paragraph. A heading,
/// paragraph, list item, blockquote and table cell are separate things to
/// read, and one English word at the front of any of them must not turn the
/// rest around.
///
/// `nexDirectionOf` itself is deliberately unchanged: it still answers from the
/// first strong character, because that is the right rule for a field being
/// typed into, where the answer must not move under the writer. The block rule
/// is [nexDominantDirectionOf].
void main() {
  const width = 420.0;

  Future<void> pump(
    WidgetTester tester,
    String source, {
    TextDirection ambient = TextDirection.ltr,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        home: Directionality(
          textDirection: ambient,
          child: Scaffold(
            body: SizedBox(
              width: width,
              child: SingleChildScrollView(child: NexMarkdown(source)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The one `Text` whose visible words are exactly [text].
  Finder block(String text) => find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (widget.data ?? widget.textSpan?.toPlainText()) == text,
    description: 'Text("$text")',
  );

  /// The direction and alignment the block with [text] was laid out in.
  ({TextDirection direction, TextAlign align}) rendered(
    WidgetTester tester,
    String text,
  ) {
    final finder = block(text);
    expect(finder, findsOneWidget, reason: 'no block with text "$text"');
    final widget = tester.widget<Text>(finder);
    return (
      direction: widget.textDirection!,
      align: widget.textAlign ?? TextAlign.start,
    );
  }

  TextDirection documentDirection(WidgetTester tester) =>
      Directionality.of(tester.element(find.byType(MarkdownBody)));

  group('the document and each block decide for themselves', () {
    testWidgets('a Persian document that opens with an English word is RTL', (
      tester,
    ) async {
      await pump(
        tester,
        'Nex\n\nیک برنامهٔ فارسی برای نگه‌داشتن یادداشت‌های روزانه است و '
        'همهٔ نوشته‌هایش را در همین دستگاه می‌ماند.',
        ambient: TextDirection.ltr,
      );
      expect(documentDirection(tester), TextDirection.rtl);
      expect(rendered(tester, 'Nex').direction, TextDirection.ltr);
      expect(
        rendered(
          tester,
          'یک برنامهٔ فارسی برای نگه‌داشتن یادداشت‌های روزانه است و '
          'همهٔ نوشته‌هایش را در همین دستگاه می‌ماند.',
        ).direction,
        TextDirection.rtl,
      );
    });

    testWidgets('an English document is LTR in a Persian interface', (
      tester,
    ) async {
      await pump(
        tester,
        '# Release notes\n\nA short English paragraph about the release.',
        ambient: TextDirection.rtl,
        locale: const Locale('fa'),
      );
      expect(documentDirection(tester), TextDirection.ltr);
      expect(rendered(tester, 'Release notes').direction, TextDirection.ltr);
    });

    testWidgets('a Persian paragraph inside an English document stays RTL', (
      tester,
    ) async {
      await pump(
        tester,
        '# English heading\n\nاین یک پاراگراف فارسی است که در سند انگلیسی '
        'هم باید راست‌به‌چپ بماند.\n\nAn English paragraph after it.',
        ambient: TextDirection.ltr,
      );
      expect(documentDirection(tester), TextDirection.rtl);
      expect(rendered(tester, 'English heading').direction, TextDirection.ltr);
      expect(
        rendered(
          tester,
          'این یک پاراگراف فارسی است که در سند انگلیسی '
          'هم باید راست‌به‌چپ بماند.',
        ).direction,
        TextDirection.rtl,
      );
    });

    testWidgets('an English-leading Persian paragraph remains RTL', (
      tester,
    ) async {
      const text =
          'Nex را باز کن و از منوی بالا گزینهٔ یادداشت تازه را انتخاب کن.';
      await pump(tester, text);
      expect(rendered(tester, text).direction, TextDirection.rtl);
    });

    testWidgets('a Persian-leading English paragraph is LTR', (tester) async {
      const text =
          'سلام، this paragraph continues in English and every following word '
          'is English too, so it reads left to right.';
      await pump(tester, text);
      expect(rendered(tester, text).direction, TextDirection.ltr);
    });

    testWidgets('a heading is decided by itself, not by the document', (
      tester,
    ) async {
      await pump(
        tester,
        '# سرتیتر پارسی\n\n## An English heading',
        ambient: TextDirection.ltr,
      );
      expect(rendered(tester, 'سرتیتر پارسی').direction, TextDirection.rtl);
      expect(
        rendered(tester, 'An English heading').direction,
        TextDirection.ltr,
      );
    });

    testWidgets('a block with no strong letters keeps the document direction', (
      tester,
    ) async {
      await pump(
        tester,
        'یک متن فارسی.\n\n۱۲:۳۰ — ۱۴۲۰\n\n!!!',
        ambient: TextDirection.ltr,
      );
      expect(documentDirection(tester), TextDirection.rtl);
      expect(rendered(tester, '۱۲:۳۰ — ۱۴۲۰').direction, TextDirection.rtl);
      expect(rendered(tester, '!!!').direction, TextDirection.rtl);
    });
  });

  group('nested lists', () {
    testWidgets('each item takes its own direction', (tester) async {
      await pump(
        tester,
        '- مورد نخست\n'
        '  - An English nested item\n'
        '  - مورد تودرتوی دوم\n',
        ambient: TextDirection.ltr,
      );
      expect(rendered(tester, 'مورد نخست').direction, TextDirection.rtl);
      expect(
        rendered(tester, 'An English nested item').direction,
        TextDirection.ltr,
      );
      expect(rendered(tester, 'مورد تودرتوی دوم').direction, TextDirection.rtl);
      // The list's own layout follows the document, so the bullets are on the
      // leading edge of a Persian document.
      final bullet = find.text('•').first;
      expect(tester.getCenter(bullet).dx, greaterThan(width / 2));
    });

    testWidgets('an English-leading Persian item stays RTL', (tester) async {
      const item = 'Nex را نصب کن و بعد کتابخانه را باز کن';
      await pump(tester, '- $item\n');
      expect(rendered(tester, item).direction, TextDirection.rtl);
    });

    testWidgets('task list text keeps its direction and its checkbox', (
      tester,
    ) async {
      const item = 'خرید شیر و نان';
      await pump(tester, '- [ ] $item\n');
      expect(rendered(tester, item).direction, TextDirection.rtl);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    });
  });

  group('blockquotes and tables', () {
    testWidgets('each quote takes its own direction', (tester) async {
      await pump(
        tester,
        '> این نقل قول فارسی باید راست‌به‌چپ باشد.\n\n'
        '> This quoted English sentence stays left to right.\n',
        ambient: TextDirection.ltr,
      );
      expect(
        rendered(tester, 'این نقل قول فارسی باید راست‌به‌چپ باشد.').direction,
        TextDirection.rtl,
      );
      expect(
        rendered(
          tester,
          'This quoted English sentence stays left to right.',
        ).direction,
        TextDirection.ltr,
      );
    });

    testWidgets('each table cell takes its own direction', (tester) async {
      await pump(
        tester,
        '| نام | Name |\n| --- | --- |\n| دفتر | notebook |\n| کتاب | book |\n',
        ambient: TextDirection.ltr,
      );
      expect(rendered(tester, 'نام').direction, TextDirection.rtl);
      expect(rendered(tester, 'Name').direction, TextDirection.ltr);
      expect(rendered(tester, 'دفتر').direction, TextDirection.rtl);
      expect(rendered(tester, 'notebook').direction, TextDirection.ltr);
      expect(rendered(tester, 'کتاب').direction, TextDirection.rtl);
    });

    testWidgets('inside a cell, an English-leading Persian stays RTL', (
      tester,
    ) async {
      const cell = 'Nex تنظیمات و کتابخانه';
      await pump(tester, '| یک | دو |\n| --- | --- |\n| $cell | x |\n');
      expect(rendered(tester, cell).direction, TextDirection.rtl);
    });

    testWidgets('an explicit cell alignment still wins', (tester) async {
      await pump(tester, '| a | b |\n| :--- | ---: |\n| one | two |\n');
      expect(rendered(tester, 'one').align, TextAlign.left);
      expect(rendered(tester, 'two').align, TextAlign.right);
    });
  });

  group('code, links, numbers and punctuation', () {
    testWidgets('an inline code span keeps its paragraph and its style', (
      tester,
    ) async {
      const source = 'برای اجرای آزمون‌ها `flutter test` را بزن.';
      await pump(tester, source);
      const visible = 'برای اجرای آزمون‌ها flutter test را بزن.';
      final paragraph = tester.widget<Text>(block(visible));
      expect(paragraph.textDirection, TextDirection.rtl);
      final span = (paragraph.textSpan! as TextSpan).children!
          .whereType<TextSpan>()
          .firstWhere((span) => span.text == 'flutter test');
      expect(span.style?.fontFamily, 'monospace');
    });

    testWidgets('an inline code span reports its own text when tapped', (
      tester,
    ) async {
      final copied = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NexMarkdown(
              '`flutter test`',
              selectable: false,
              onCopyCode: copied.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('flutter test', findRichText: true));
      await tester.pumpAndSettle();
      expect(copied, ['flutter test']);
    });

    testWidgets('a fenced block is LTR inside a Persian document', (
      tester,
    ) async {
      const code = 'void main() {\n  print("سلام");\n}';
      await pump(tester, 'یک توضیح فارسی.\n\n```dart\n$code\n```\n');
      final finder = block(code);
      expect(finder, findsOneWidget);
      final widget = tester.widget<Text>(finder);
      expect(widget.textDirection, TextDirection.ltr);
      expect(Directionality.of(tester.element(finder)), TextDirection.ltr);
    });

    testWidgets('URLs and digits inside an RTL paragraph stay one paragraph', (
      tester,
    ) async {
      const text =
          'این لینک https://example.com/abc و این شماره ۰۹۱۲۳۴۵۶۷۸۹ را ببین.';
      await pump(tester, text, ambient: TextDirection.ltr);
      final widget = tester.widget<Text>(block(text));
      expect(widget.textDirection, TextDirection.rtl);
      expect(widget.textSpan!.toPlainText(), text);
    });

    testWidgets('a link in a Persian paragraph is tappable and RTL', (
      tester,
    ) async {
      final followed = <String>[];
      const text = '[راهنما](https://nex.app/guide)';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NexMarkdown(text, selectable: false, onTapLink: followed.add),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(block('راهنما')).textDirection,
        TextDirection.rtl,
      );
      await tester.tap(find.text('راهنما', findRichText: true));
      await tester.pumpAndSettle();
      expect(followed, ['https://nex.app/guide']);
    });
  });

  group('the old first-strong rule is untouched', () {
    test('nexDirectionOf still answers from the first strong letter', () {
      expect(nexDirectionOf('Nex را باز کن'), TextDirection.ltr);
      expect(nexDirectionOf('سلام hello'), TextDirection.rtl);
      expect(nexDirectionOf('۱۲:۳۰'), isNull);
      expect(nexDirectionOf(''), isNull);
    });

    test('dominance counts the letters, and ties fall back to the first', () {
      expect(nexDominantDirectionOf('Nex را باز کن'), TextDirection.rtl);
      expect(nexDominantDirectionOf('سلام this is English'), TextDirection.ltr);
      expect(nexDominantDirectionOf('hello سلام'), TextDirection.ltr);
      expect(nexDominantDirectionOf('سلام دوست من hello'), TextDirection.rtl);
      expect(nexDominantDirectionOf('۱۲:۳۰ — ۱۴۲۰'), isNull);
      expect(nexDominantDirectionOf(null), isNull);
      expect(nexDominantDirectionOf('🙂 !!!'), isNull);
    });
  });

  group('the interface locale does not decide', () {
    testWidgets('a Persian interface does not turn an English block around', (
      tester,
    ) async {
      const text = 'A plain English sentence for a Persian reader.';
      await pump(
        tester,
        text,
        ambient: TextDirection.rtl,
        locale: const Locale('fa'),
      );
      expect(rendered(tester, text).direction, TextDirection.ltr);
      expect(rendered(tester, text).align, TextAlign.start);
    });

    testWidgets('an English interface does not turn a Persian block around', (
      tester,
    ) async {
      const text = 'یک جملهٔ فارسی برای خوانندهٔ انگلیسی‌زبان.';
      await pump(
        tester,
        text,
        ambient: TextDirection.ltr,
        locale: const Locale('en'),
      );
      expect(rendered(tester, text).direction, TextDirection.rtl);
      expect(rendered(tester, text).align, TextAlign.start);
    });
  });

  group('formatting is preserved', () {
    testWidgets('bold, italic and strike keep their styles inside a block', (
      tester,
    ) async {
      const text = 'این **پررنگ** و این *مورب* و ~~خط‌خورده~~ است.';
      const visible = 'این پررنگ و این مورب و خط‌خورده است.';
      await pump(tester, text);
      final widget = tester.widget<Text>(block(visible));
      expect(widget.textDirection, TextDirection.rtl);
      final spans = (widget.textSpan! as TextSpan).children!
          .whereType<TextSpan>()
          .toList();
      final bold = spans.firstWhere((span) => span.text == 'پررنگ');
      expect(bold.style?.fontWeight, FontWeight.w700);
      final italic = spans.firstWhere((span) => span.text == 'مورب');
      expect(italic.style?.fontStyle, FontStyle.italic);
      final struck = spans.firstWhere((span) => span.text == 'خط‌خورده');
      expect(struck.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('a note that keeps its line breaks keeps them', (tester) async {
      const text = 'خط اول\nخط دوم';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NexMarkdown(text, preserveLineBreaks: true)),
        ),
      );
      await tester.pumpAndSettle();
      final widget = tester.widget<Text>(block(text));
      expect(widget.textSpan!.toPlainText(), text);
      expect(widget.textDirection, TextDirection.rtl);
    });

    testWidgets('a hard line break is kept inside a paragraph', (tester) async {
      const source = 'خط اول  \nخط دوم';
      await pump(tester, source);
      final widget = tester.widget<Text>(block('خط اول\nخط دوم'));
      expect(widget.textDirection, TextDirection.rtl);
    });
  });

  testWidgets('the rendered document still says what the source says', (
    tester,
  ) async {
    const source = '# عنوان\n\nیک پاراگراف فارسی.\n\n- یک\n- دو\n\n> نقل قول\n';
    await pump(tester, source);
    expect(block('عنوان'), findsOneWidget);
    expect(block('یک پاراگراف فارسی.'), findsOneWidget);
    expect(block('یک'), findsOneWidget);
    expect(block('نقل قول'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
