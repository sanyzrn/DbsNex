import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  TextSpan spanOf(
    String code,
    NexCodeLanguage language, {
    Brightness brightness = Brightness.light,
  }) {
    final scheme = brightness == Brightness.dark
        ? ThemeData.dark().colorScheme
        : ThemeData.light().colorScheme;
    return TextSpan(
      children: nexHighlightCode(
        code,
        language,
        style: const TextStyle(fontFamily: 'monospace'),
        scheme: scheme,
      ),
    );
  }

  const html = '''<!-- marker -->
<section data-title="A > B">A &amp; B</section>
<script>const example = "<div>";</script>
''';
  const css = '''/* marker */
@media (max-width: 40rem) {
  .card:hover { color: #aabbcc; content: "{"; padding: 1.25rem; }
}
''';
  const php = r'''<?php
#[Route('/')]
FUNCTION greet(string $نام) {
  # marker
  $message = <<<'BODY'
سلام
BODY;
  return $message;
}
?>
''';

  TextStyle? styleOf(TextSpan span, String token) => span.children!
      .whereType<TextSpan>()
      .firstWhere((piece) => piece.text == token)
      .style;

  group('highlighting never changes the code', () {
    const samples = {
      NexCodeLanguage.dart: '// note\nfinal String name = r"a\\b";\nvoid main() {\n\tprint(name); // hi\n}\n',
      NexCodeLanguage.javascript: '/* block */\nconst url = `https://example.com/\$id`;\nconsole.log(url);\n',
      NexCodeLanguage.python:
          '# note\nname = """a\nb"""\nprint(f"hello {name}")\n',
      NexCodeLanguage.json: '{"name": "nex", "count": 12, "ok": true}\n',
      NexCodeLanguage.html: html,
      NexCodeLanguage.css: css,
      NexCodeLanguage.php: php,
      NexCodeLanguage.plainText: '```\nnot fenced here\n```\n',
    };

    for (final entry in samples.entries) {
      test('${entry.key.id} spans join back into the source', () {
        final text = spanOf(entry.value, entry.key).toPlainText();
        expect(text, entry.value);
      });

      test('${entry.key.id} keeps every character in dark mode too', () {
        final text = spanOf(
          entry.value,
          entry.key,
          brightness: Brightness.dark,
        ).toPlainText();
        expect(text, entry.value);
      });
    }

    test('a supported language colours more than one kind of token', () {
      final colors = <Color?>{
        for (final span in spanOf(
          'const x = 1; // comment\nfinal name = "text";',
          NexCodeLanguage.dart,
        ).children!)
          span.style?.color,
      };

      expect(colors.length, greaterThan(2));
    });

    test('plain text is one unstyled span', () {
      const code = 'const x = 1; // a comment that stays plain';
      final spans = nexHighlightCode(
        code,
        NexCodeLanguage.plainText,
        style: const TextStyle(),
        scheme: ThemeData.light().colorScheme,
      );

      expect(spans, hasLength(1));
      expect(spans.single.text, code);
      expect(spans.single.style, isNull);
    });
  });

  test('HTML highlights tags, attributes, values, entities and comments', () {
    final span = spanOf(html, NexCodeLanguage.html);
    expect(styleOf(span, '<section')?.fontWeight, FontWeight.w600);
    expect(styleOf(span, 'data-title')?.color, isNotNull);
    expect(
      styleOf(span, 'data-title')?.color,
      isNot(styleOf(span, '<section')?.color),
    );
    expect(styleOf(span, '"A > B"')?.color, isNotNull);
    expect(styleOf(span, '&amp;')?.color, isNotNull);
    expect(styleOf(span, '<!-- marker -->')?.fontStyle, FontStyle.italic);
    expect(styleOf(span, 'const example = "<div>";'), isNull);
  });

  test(
    'HTML roles keep distinct colours with readable contrast in both themes',
    () {
      const source = '<!-- note --><p id="a" title=plain>';
      for (final theme in [ThemeData.light(), ThemeData.dark()]) {
        final span = spanOf(
          source,
          NexCodeLanguage.html,
          brightness: theme.brightness,
        );
        final colors = [
          for (final token in ['<!-- note -->', '<p', 'id', '"a"', 'plain'])
            styleOf(span, token)!.color!,
        ];
        expect(colors.toSet(), hasLength(colors.length));
        for (final color in colors) {
          expect(
            nexContrast(color, theme.colorScheme.surfaceContainerHighest),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );

  test('a JavaScript template literal keeps its colour across lines', () {
    const code = 'const page = `hello\nworld`;\nconst n = 1;';
    final span = spanOf(code, NexCodeLanguage.javascript);

    expect(
      span.children!.whereType<TextSpan>().any(
        (piece) => piece.text == '`hello\nworld`',
      ),
      isTrue,
    );
  });

  test('a quote that never closes still stops at its own line', () {
    const code = "const broken = 'oops\nconst n = 1;";
    final span = spanOf(code, NexCodeLanguage.javascript);

    expect(
      span.children!.whereType<TextSpan>().any(
        (piece) => piece.text == "'oops",
      ),
      isTrue,
    );
  });

  test('a Dart raw string ends at its own quote, backslash and all', () {
    const code =
        r"final path = r'C:\';"
        '\nfinal n = 1;';
    final span = spanOf(code, NexCodeLanguage.dart);

    expect(
      span.children!.whereType<TextSpan>().any(
        (piece) => piece.text == r"r'C:\'",
      ),
      isTrue,
    );
  });

  test('CSS highlights selectors, properties, values and at-rules', () {
    final span = spanOf(css, NexCodeLanguage.css);
    expect(styleOf(span, '@media')?.fontWeight, FontWeight.w600);
    expect(styleOf(span, '.card')?.fontWeight, FontWeight.w600);
    expect(styleOf(span, ':hover')?.fontWeight, FontWeight.w600);
    expect(styleOf(span, 'color')?.color, isNotNull);
    expect(styleOf(span, 'content'), styleOf(span, 'color'));
    expect(styleOf(span, '#aabbcc'), styleOf(span, '1.25rem'));
    expect(styleOf(span, '1.25rem')?.color, isNotNull);
    expect(styleOf(span, '/* marker */')?.fontStyle, FontStyle.italic);
  });

  test('PHP highlights tags, keywords, variables and nowdocs', () {
    final span = spanOf(php, NexCodeLanguage.php);
    expect(styleOf(span, '<?php'), styleOf(span, '?>'));
    expect(styleOf(span, 'FUNCTION')?.fontWeight, FontWeight.w600);
    expect(styleOf(span, r'$نام')?.color, isNotNull);
    expect(styleOf(span, r'$نام'), isNot(styleOf(span, 'FUNCTION')));
    expect(styleOf(span, '#[')?.fontStyle, isNot(FontStyle.italic));
    expect(styleOf(span, '# marker')?.fontStyle, FontStyle.italic);
    expect(styleOf(span, "<<<'BODY'\nسلام\nBODY"), styleOf(span, "'/'"));
    expect(styleOf(span, "<<<'BODY'\nسلام\nBODY")?.color, isNotNull);
  });

  group('a long source is coloured once and drawn a chunk at a time', () {
    const source =
        '// first\n'
        '/* opened before the cut\n'
        ' * still the same comment\n'
        ' */\n'
        'final x = 1;\n';
    final spans = nexHighlightCode(
      source,
      NexCodeLanguage.dart,
      style: const TextStyle(),
      scheme: ThemeData.light().colorScheme,
    );

    test('every slice joins back into its own part of the source', () {
      for (final (start, end) in [
        (0, 9),
        (4, 20),
        (20, 55),
        (0, source.length),
        (source.length - 2, source.length),
      ]) {
        final sliced = nexSliceCodeSpans(spans, start, end);
        expect(
          sliced.map((piece) => piece.text).join(),
          source.substring(start, end),
          reason: '$start–$end',
        );
      }
    });

    test('a comment cut in half keeps its style on both sides', () {
      final first = nexSliceCodeSpans(spans, 0, 25);
      final second = nexSliceCodeSpans(spans, 25, 60);
      for (final piece in [first, second]) {
        expect(
          piece.any((span) => span.style?.fontStyle == FontStyle.italic),
          isTrue,
        );
      }
    });

    test('offsets outside the source are clamped, not thrown', () {
      expect(
        nexSliceCodeSpans(spans, -8, 5).map((piece) => piece.text).join(),
        source.substring(0, 5),
      );
      expect(nexSliceCodeSpans(spans, 6, 2), isEmpty);
      expect(
        nexSliceCodeSpans(spans, source.length + 10, source.length + 20),
        isEmpty,
      );
    });

    testWidgets('a widget given spans paints them without tokenizing again', (
      tester,
    ) async {
      final chunk = nexSliceCodeSpans(spans, 20, 55);
      await tester.pumpWidget(
        MaterialApp(
          theme: nexLightTheme(),
          home: Scaffold(
            body: NexCodeText(
              source.substring(20, 55),
              language: NexCodeLanguage.dart,
              spans: chunk,
            ),
          ),
        ),
      );
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byType(NexCodeText),
          matching: find.byType(RichText),
        ),
      );
      expect(rich.text.toPlainText(), source.substring(20, 55));
      expect(
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.style?.fontStyle == FontStyle.italic) {
            return false;
          }
          return true;
        }),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('code reads left to right in a Persian interface', () {
    testWidgets('the text direction is LTR whatever the page is', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: nexLightTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: NexCodeText(
                'void main() {\n\tprint("سلام");\n}',
                language: NexCodeLanguage.dart,
              ),
            ),
          ),
        ),
      );

      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byType(NexCodeText),
          matching: find.byType(RichText),
        ),
      );
      expect(rich.textDirection, TextDirection.ltr);
      expect(rich.text.toPlainText(), contains('print("سلام")'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a selectable snippet is LTR as well', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: nexDarkTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: NexCodeText(
                'print("سلام")',
                language: NexCodeLanguage.python,
                selectable: true,
              ),
            ),
          ),
        ),
      );

      final field = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(field.textDirection, TextDirection.ltr);
      expect(field.style?.fontFamily, 'monospace');
      expect(tester.takeException(), isNull);
    });
  });
}
