import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// A link card shows the caption someone wrote ahead of what the page says
/// about itself, and the page's own name and description only without one.
void main() {
  Note link({String? caption, String? title, String? linkExcerpt}) => Note(
    id: 'n1',
    type: NoteType.link,
    content: 'https://example.com/a',
    caption: caption,
    title: title,
    linkExcerpt: linkExcerpt,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  test('a caption outranks the page title and description', () {
    expect(
      link(
        caption: 'read later',
        title: 'Page',
        linkExcerpt: 'About',
      ).displayText,
      'read later',
    );
  });

  test('without a caption the page title, then its description', () {
    expect(link(title: 'Page', linkExcerpt: 'About').displayText, 'Page');
    expect(link(linkExcerpt: 'About').displayText, 'About');
    expect(link().displayText, 'https://example.com/a');
  });
}
