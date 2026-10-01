import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// What Copy puts on the clipboard: the person's own words before a model's.
///
/// The hold menu and the selection bar used to copy `content ?? transcript ??
/// ocr`, so a captioned photo copied the text read out of the picture and
/// never the caption written under it.
void main() {
  Note note(
    NoteType type, {
    String? content,
    String? caption,
    String? ocrText,
    String? transcriptText,
  }) => Note(
    id: 'n1',
    type: type,
    content: content,
    caption: caption,
    ocrText: ocrText,
    transcriptText: transcriptText,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  test('a photo copies its caption, and its OCR only without one', () {
    expect(
      note(NoteType.photo, caption: 'receipt', ocrText: 'TOTAL 42').copyText,
      'receipt',
    );
    expect(
      note(NoteType.photo, caption: '  ', ocrText: 'TOTAL 42').copyText,
      'TOTAL 42',
    );
    expect(note(NoteType.photo).copyText, isNull);
  });

  test('a voice note copies its caption before its transcript', () {
    expect(
      note(
        NoteType.voice,
        caption: 'call mum',
        transcriptText: 'remember to call',
      ).copyText,
      'call mum',
    );
    expect(
      note(NoteType.voice, transcriptText: 'remember to call').copyText,
      'remember to call',
    );
  });

  test('a text note copies its words', () {
    expect(note(NoteType.text, content: 'milk').copyText, 'milk');
  });
}
