import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/app_update.dart';
import 'package:nex_client/widgets/release_notes.dart';

void main() {
  test('all intervening releases are ordered and localized independently', () {
    final latest = UpdateCheck.available(
      version: const NexVersion(2, 1, 0),
      downloadUrl: 'https://example.com/app.apk',
      notes: 'Latest EN\n<!-- nex:fa -->\nجدید',
    );
    final notes = UpdateChecker.notesSince(
      [
        {'tag_name': 'v2.0.8', 'body': 'Installed EN'},
        {'tag_name': 'v2.0.9', 'body': 'Older EN\n<!-- nex:fa -->\nقدیمی'},
        {'tag_name': 'v2.0.10', 'body': 'Middle EN\n<!-- nex:fa -->\nمیانی'},
        {'tag_name': 'v2.2.0', 'body': 'Future EN'},
        {'tag_name': 'v2.0.11', 'body': 'Draft EN', 'draft': true},
      ],
      installed: const NexVersion(2, 0, 8),
      latest: latest,
    )!;
    final en = releaseNotesFor(notes, 'en');
    final fa = releaseNotesFor(notes, 'fa');
    expect(en, contains('Latest EN'));
    expect(en, contains('Middle EN'));
    expect(en, contains('Older EN'));
    expect(en.indexOf('Latest EN'), lessThan(en.indexOf('Middle EN')));
    expect(en.indexOf('Middle EN'), lessThan(en.indexOf('Older EN')));
    expect(en, isNot(contains('Installed EN')));
    expect(en, isNot(contains('Future EN')));
    expect(en, isNot(contains('Draft EN')));
    expect(fa, contains('جدید'));
    expect(fa, contains('میانی'));
    expect(fa, contains('قدیمی'));
    expect(fa, isNot(contains('Latest EN')));
  });
}
