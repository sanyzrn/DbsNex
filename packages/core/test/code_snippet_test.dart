import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  group('a snippet survives the note it is stored in', () {
    test('every language keeps indentation, tabs, blank lines and spaces', () {
      const code = '\tif (ok) {\n\n    print("two  spaces");   \n}\n\n';
      for (final language in NexCodeLanguage.values) {
        final snippet = NexCodeSnippet(code: code, language: language);
        final parsed = NexCodeSnippet.parse(snippet.markdown);

        expect(parsed, isNotNull, reason: language.id);
        expect(parsed!.code, code, reason: language.id);
        expect(parsed.language, language, reason: language.id);
        expect(parsed.rawLanguage, isNull, reason: language.id);
        expect(parsed.markdown, snippet.markdown, reason: language.id);
      }
    });

    test('a snippet of another Markdown fence cannot close its own block', () {
      const code = '```dart\nprint("hi");\n```\n\n~~~~\nstill code\n~~~~';
      final snippet = NexCodeSnippet(
        code: code,
        language: NexCodeLanguage.dart,
      );

      expect(snippet.markdown.startsWith('````dart\n'), isTrue);
      final parsed = NexCodeSnippet.parse(snippet.markdown);

      expect(parsed, isNotNull);
      expect(parsed!.code, code);
      expect(parsed.language, NexCodeLanguage.dart);
    });

    test('an empty code block reopens empty', () {
      final snippet = NexCodeSnippet(
        code: '',
        language: NexCodeLanguage.python,
      );
      final parsed = NexCodeSnippet.parse(snippet.markdown);

      expect(parsed, isNotNull);
      expect(parsed!.code, '');
      expect(parsed.language, NexCodeLanguage.python);
    });

    test('one trailing newline after the closing fence is accepted', () {
      final parsed = NexCodeSnippet.parse('```json\n{"a": 1}\n```\n');

      expect(parsed, isNotNull);
      expect(parsed!.code, '{"a": 1}');
      expect(parsed.language, NexCodeLanguage.json);
    });

    test('a language this build does not know is kept, not renamed', () {
      final parsed = NexCodeSnippet.parse('```kotlin\nval x = 1\n```');

      expect(parsed, isNotNull);
      expect(parsed!.language, NexCodeLanguage.plainText);
      expect(parsed.rawLanguage, 'kotlin');
      expect(parsed.markdown, '```kotlin\nval x = 1\n```');
    });

    test('the aliases other tools write are understood', () {
      expect(NexCodeLanguage.fromId('js'), NexCodeLanguage.javascript);
      expect(NexCodeLanguage.fromId('JS'), NexCodeLanguage.javascript);
      expect(NexCodeLanguage.fromId('py'), NexCodeLanguage.python);
      expect(NexCodeLanguage.fromId('plaintext'), NexCodeLanguage.plainText);
      expect(NexCodeLanguage.fromId('wat'), isNull);
    });
  });

  group('only a note that is one fenced block is a snippet', () {
    test('prose before or after a fence leaves it an ordinary note', () {
      expect(NexCodeSnippet.parse('Before\n```dart\nvar x = 1;\n```'), isNull);
      expect(NexCodeSnippet.parse('```dart\nvar x = 1;\n```\nAfter'), isNull);
      expect(
        NexCodeSnippet.parse('Before\n```dart\nvar x = 1;\n```\nAfter'),
        isNull,
      );
    });

    test('an unclosed or mismatched fence is not a snippet', () {
      expect(NexCodeSnippet.parse('```dart\nvar x = 1;'), isNull);
      expect(NexCodeSnippet.parse('```dart\nvar x = 1;\n~~~'), isNull);
      expect(NexCodeSnippet.parse('   ```dart\nvar x = 1;\n } ```'), isNull);
    });

    test('an indented fence follows CommonMark', () {
      final parsed = NexCodeSnippet.parse('   ```dart\nvar x = 1;\n   ```');
      expect(parsed, isNotNull);
      expect(parsed!.code, 'var x = 1;');

      // Four spaces make an indented code block, not a fence.
      expect(NexCodeSnippet.parse('    ```dart\nvar x = 1;\n    ```'), isNull);
    });
  });

  group('previews are cheap and leave the fence behind', () {
    test('a preview is capped but still says which language it is', () {
      final code = List.generate(80, (i) => 'line $i').join('\n');
      final source = NexCodeSnippet(
        code: code,
        language: NexCodeLanguage.javascript,
      ).markdown;
      final preview = NexCodeSnippet.previewOf(source, maxChars: 40);

      expect(preview, isNotNull);
      expect(preview!.code.length, lessThanOrEqualTo(40));
      expect(preview.language, NexCodeLanguage.javascript);
      // The full parse still has every line.
      expect(NexCodeSnippet.parse(source)!.code, code);
    });

    test('the Markdown preview of a snippet is its code, not its fence', () {
      const code = 'const x = `a`;\n';
      final source = NexCodeSnippet(
        code: code,
        language: NexCodeLanguage.javascript,
      ).markdown;

      expect(NexMarkdownText.preview(source), code);
    });
  });
}
