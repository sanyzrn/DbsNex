import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/assistant_citations.dart';

/// The markers an assistant reply carries for the app, taken out of the prose.
void main() {
  const a = '0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b';
  const b = '0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5c';

  test('a Sources line becomes ids and leaves the answer', () {
    final reply = NexCitedReply.parse('The code is 4471.\nSources: [$a] [$b]');
    expect(reply.text, 'The code is 4471.');
    expect(reply.noteIds, [a, b]);
    expect(reply.general, isFalse);
  });

  test('ids in the prose are taken out too, once each, in order', () {
    final reply = NexCitedReply.parse('See [$b] and [$a, $b].\n\nمنابع: [$a]');
    expect(reply.text, 'See and.');
    expect(reply.noteIds, [b, a]);
  });

  test('only known ids are kept, but every id leaves the text', () {
    final reply = NexCitedReply.parse('Done.\nSources: [$a] [$b]', known: {a});
    expect(reply.text, 'Done.');
    expect(reply.noteIds, [a]);
  });

  test('[general] marks an answer that is not from the notes', () {
    final reply = NexCitedReply.parse('[general] Paris.');
    expect(reply.general, isTrue);
    expect(reply.text, 'Paris.');
    expect(reply.noteIds, isEmpty);
  });

  test('ordinary brackets and Markdown are left alone', () {
    const text = '- [x] done\n- [link](https://example.com)';
    final reply = NexCitedReply.parse(text);
    expect(reply.text, text);
    expect(reply.noteIds, isEmpty);
  });
}
