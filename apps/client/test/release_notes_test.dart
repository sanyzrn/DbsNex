import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/release_notes.dart';

/// The update screen's notes in the reader's language (LOC-05).
void main() {
  const both =
      '- **Faster search.**\n\n$releaseNotesPersianMarker\n- **جست‌وجوی سریع‌تر.**\n';

  test('a Persian reader gets the Persian notes', () {
    expect(releaseNotesFor(both, 'fa'), '- **جست‌وجوی سریع‌تر.**');
  });

  test('everyone else gets the English, without the Persian', () {
    expect(releaseNotesFor(both, 'en'), '- **Faster search.**');
  });

  test('a release from before Persian notes reads as it always did', () {
    expect(releaseNotesFor('- **Old.**\n', 'fa'), '- **Old.**');
  });
}
