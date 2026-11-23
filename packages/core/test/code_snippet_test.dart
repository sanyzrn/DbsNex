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

    test('blank lines after the closing fence are still the same block', () {
      for (final tail in ['\n', '\n\n', '  \n', '\n\n  \n']) {
        final parsed = NexCodeSnippet.parse('```dart\nvar x = 1;\n```$tail');

        expect(parsed, isNotNull, reason: tail);
        expect(parsed!.code, 'var x = 1;', reason: tail);
        expect(parsed.language, NexCodeLanguage.dart, reason: tail);
      }
      // Prose after the fence is still an ordinary note, not a snippet.
      expect(NexCodeSnippet.parse('```dart\nvar x = 1;\n```\n\nProse'), isNull);
    });

    test('a language this build does not know is kept, not renamed', () {
      final parsed = NexCodeSnippet.parse('```zig\nconst x = 1;\n```');

      expect(parsed, isNotNull);
      expect(parsed!.language, NexCodeLanguage.plainText);
      expect(parsed.rawLanguage, 'zig');
      expect(parsed.markdown, '```zig\nconst x = 1;\n```');
    });

    test('the aliases other tools write are understood', () {
      expect(NexCodeLanguage.fromId('js'), NexCodeLanguage.javascript);
      expect(NexCodeLanguage.fromId('JS'), NexCodeLanguage.javascript);
      expect(NexCodeLanguage.fromId('py'), NexCodeLanguage.python);
      expect(NexCodeLanguage.fromId('c#'), NexCodeLanguage.csharp);
      expect(NexCodeLanguage.fromId('tsx'), NexCodeLanguage.typescript);
      expect(NexCodeLanguage.fromId('yml'), NexCodeLanguage.yaml);
      expect(NexCodeLanguage.fromId('HTM'), NexCodeLanguage.html);
      expect(NexCodeLanguage.fromId('CSS'), NexCodeLanguage.css);
      expect(NexCodeLanguage.fromId('phtml'), NexCodeLanguage.php);
      expect(NexCodeLanguage.fromId('plaintext'), NexCodeLanguage.plainText);
      expect(NexCodeLanguage.fromId('wat'), isNull);
    });
  });

  test('editing the code keeps the whole info string (2.8.19)', () {
    final read = NexCodeSnippet.parse('```js filename=app.js\nlet a=1\n```')!;
    expect(read.language, NexCodeLanguage.fromId('js'));
    expect(
      read.withCode('let a=2').markdown,
      '```js filename=app.js\nlet a=2\n```',
    );
    // Choosing a language replaces it.
    expect(
      read.withLanguage(NexCodeLanguage.plainText).markdown,
      startsWith('```${NexCodeLanguage.plainText.id}\n'),
    );
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

    test('two fenced blocks keep all of the original Markdown', () {
      const first = '```dart\nprint(1);\n```';
      const second = '```dart\nprint(2);\n```';
      for (final between in ['\n', '\n\nExplanation.\n\n']) {
        final source = '$first$between$second';
        expect(NexCodeSnippet.parse(source), isNull);
        expect(NexCodeSnippet.previewOf(source, maxChars: 3), isNull);
      }
    });

    test('CRLF wrappers preserve the code and its internal line endings', () {
      const code = '\tprint(1);  \r\nprint(2);\r\n';
      final snippet = NexCodeSnippet.parse('```dart\r\n$code\r\n```\r\n');
      expect(snippet?.language, NexCodeLanguage.dart);
      expect(snippet?.code, code);
      expect(NexCodeSnippet.parse(snippet!.markdown)?.code, code);
      const bareCarriageReturn = NexCodeSnippet(code: 'text\r');
      expect(
        NexCodeSnippet.parse(bareCarriageReturn.markdown)?.code,
        bareCarriageReturn.code,
      );
    });

    test('an unknown language with a backtick keeps a valid tilde fence', () {
      final snippet = NexCodeSnippet.parse('~~~custom`id\nline\n~~~')!;
      final edited = snippet.withCode('first\n~~~\nlast');
      expect(edited.markdown, '~~~~custom`id\nfirst\n~~~\nlast\n~~~~');
      expect(NexCodeSnippet.parse(edited.markdown)?.code, edited.code);
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
