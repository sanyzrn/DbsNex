import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// The predicate this replaces answered one question — "is it Markdown?" — and
/// every other showable format fell into the same bucket as a `.bin`.
void main() {
  group('the extension decides', () {
    test('Markdown, in every spelling it has in the wild', () {
      for (final name in ['a.md', 'a.markdown', 'a.mdown', 'a.mkd']) {
        expect(NexFileKinds.of(path: '/x/$name'), NexFileKind.markdown, reason: name);
      }
      expect(NexFileKinds.of(path: '/x/NOTES.MD'), NexFileKind.markdown);
    });

    test('a text file is plain text, not Markdown', () {
      // The distinction the old predicate could not make, and the reason it
      // matters: a `.txt` whose line begins with `#` is a line, not a heading.
      expect(NexFileKinds.of(path: '/x/notes.txt'), NexFileKind.plainText);
      expect(NexFileKinds.of(path: '/x/run.log'), NexFileKind.plainText);
    });

    test('source and configuration are code', () {
      for (final name in ['main.dart', 'a.py', 'a.json', 'a.yml', 'a.sh']) {
        expect(NexFileKinds.of(path: '/x/$name'), NexFileKind.code, reason: name);
      }
    });

    test('media', () {
      expect(NexFileKinds.of(path: '/x/a.png'), NexFileKind.image);
      expect(NexFileKinds.of(path: '/x/a.mp3'), NexFileKind.audio);
      expect(NexFileKinds.of(path: '/x/a.mp4'), NexFileKind.video);
    });

    test('documents this app cannot open yet are still named as documents', () {
      expect(NexFileKinds.of(path: '/x/a.pdf'), NexFileKind.document);
      expect(NexFileKinds.of(path: '/x/a.docx'), NexFileKind.document);
    });

    test('anything unrecognised stays other', () {
      expect(NexFileKinds.of(path: '/x/a.bin'), NexFileKind.other);
      expect(NexFileKinds.of(path: '/x/archive.zip'), NexFileKind.other);
      expect(NexFileKinds.of(path: null), NexFileKind.other);
      expect(NexFileKinds.of(path: ''), NexFileKind.other);
    });

    test('a dotfile has a name, not an extension', () {
      // `.gitignore` is not a file of type "gitignore", and guessing that it
      // is would render a config file as one.
      expect(NexFileKinds.extensionOf('/x/.gitignore'), '');
      expect(NexFileKinds.of(path: '/x/.gitignore'), NexFileKind.other);
      expect(NexFileKinds.extensionOf('/x/no-extension'), '');
      expect(NexFileKinds.extensionOf(r'C:\notes\plan.md'), 'md');
    });
  });

  group('a MIME type overrules the name only when it says something', () {
    test('a specific type wins over a name that has nothing to say', () {
      expect(
        NexFileKinds.of(path: '/x/notes', mimeType: 'text/markdown'),
        NexFileKind.markdown,
      );
      expect(
        NexFileKinds.of(path: '/x/a', mimeType: 'text/markdown; charset=utf-8'),
        NexFileKind.markdown,
      );
      expect(
        NexFileKinds.of(path: '/x/download', mimeType: 'audio/mpeg'),
        NexFileKind.audio,
      );
    });

    test('a generic type does not win, because it knows nothing', () {
      // Android's share sheet hands out octet-stream freely. Believing it
      // would hide every Markdown file that arrived through a share.
      expect(
        NexFileKinds.of(
          path: '/x/notes.md',
          mimeType: 'application/octet-stream',
        ),
        NexFileKind.markdown,
      );
      expect(
        NexFileKinds.of(path: '/x/song.mp3', mimeType: '*/*'),
        NexFileKind.audio,
      );
    });

    test('an unknown text type is treated as source', () {
      expect(
        NexFileKinds.of(path: '/x/page', mimeType: 'text/html'),
        NexFileKind.code,
      );
    });

    test('SVG is an image this app cannot draw, so it stays a named file', () {
      expect(
        NexFileKinds.of(path: '/x/logo.svg', mimeType: 'image/svg+xml'),
        NexFileKind.other,
      );
    });
  });

  test('isText covers exactly what is read off disk as text', () {
    expect(NexFileKind.markdown.isText, isTrue);
    expect(NexFileKind.plainText.isText, isTrue);
    expect(NexFileKind.code.isText, isTrue);
    expect(NexFileKind.table.isText, isTrue);
    expect(NexFileKind.image.isText, isFalse);
    expect(NexFileKind.audio.isText, isFalse);
    expect(NexFileKind.video.isText, isFalse);
    expect(NexFileKind.document.isText, isFalse);
    expect(NexFileKind.other.isText, isFalse);
  });
}
