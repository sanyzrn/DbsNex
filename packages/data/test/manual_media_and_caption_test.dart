import 'dart:async';
import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

class _Reader implements AIAdapter {
  int images = 0, audio = 0;
  bool fail = false;
  Completer<OCRText>? pending;
  Completer<Summary>? summaryPending;
  bool embedEnabled = false;
  final embedded = <String>[];
  @override
  Future<OCRText>? ocr(ImageRef image) async {
    images++;
    if (fail) throw const AiUnavailableException();
    return pending == null
        ? const OCRText(text: 'A red flower with green leaves.')
        : pending!.future;
  }

  @override
  Future<Transcript>? transcribe(AudioRef audio) async {
    this.audio++;
    return const Transcript(text: 'Buy fresh bread tomorrow.');
  }

  @override
  Future<Vector>? embed(String text) {
    if (!embedEnabled) return null;
    embedded.add(text);
    return Future.value(const Vector([1, 0]));
  }

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) => null;
  @override
  Future<Summary>? summarize(Note note) => summaryPending?.future;
}

void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late _Reader reader;
  late EnrichmentService ai;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_manual_media_');
    db = NexDatabase.open('${tmp.path}/nex.sqlite');
    repo = SqliteNoteRepository(db, localDeviceId: 'test');
    reader = _Reader();
    ai = EnrichmentService(
      repo: repo,
      adapter: reader,
      capabilities: AiCapabilities.allOn,
    );
  });
  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note insert(
    NoteType type, {
    String extension = 'jpg',
    String? mime,
    String? caption,
  }) {
    final now = DateTime.now().toUtc();
    final file = File('${tmp.path}/${newUuidV7()}.$extension')
      ..writeAsBytesSync([1, 2, 3]);
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: type,
        content: type == NoteType.text
            ? 'Original writing.'
            : 'my-file.$extension',
        caption: caption,
        mediaUri: file.path,
        mediaHash: 'hash-${file.path}',
        mimeType: mime,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  test('capture and startup enrichment never read media', () async {
    final photo = insert(NoteType.photo);
    final voice = insert(NoteType.voice, extension: 'm4a');
    await ai.enrichNote(photo.id);
    await ai.enrichNote(voice.id);
    await ai.backfill();
    expect(reader.images, 0);
    expect(reader.audio, 0);
    expect(repo.getById(photo.id)!.ocrText, isNull);
    expect(repo.getById(voice.id)!.transcriptText, isNull);
  });

  test(
    'unread media captions remain searchable by meaning without reading their media',
    () async {
      reader.embedEnabled = true;
      final photo = insert(NoteType.photo, caption: 'Gardening receipt');
      final voice = insert(
        NoteType.voice,
        extension: 'm4a',
        caption: 'Bank appointment',
      );
      final text = insert(NoteType.text);
      expect(await ai.backfill(), 3);
      for (final note in [photo, voice, text]) {
        expect(repo.getEmbedding(note.id), isNotNull);
      }
      expect(
        reader.embedded,
        containsAll([
          'Gardening receipt',
          'Bank appointment',
          'Original writing.',
        ]),
      );
      expect(reader.images, 0);
      expect(reader.audio, 0);
    },
  );

  test(
    'explicit image description and transcription persist and become searchable',
    () async {
      final photo = insert(NoteType.photo);
      final voice = insert(NoteType.voice, extension: 'm4a');
      expect(await ai.readMediaOnDemand(photo.id), contains('flower'));
      expect(await ai.readMediaOnDemand(voice.id), contains('bread'));
      expect(
        repo.search(const SearchFilters(query: 'flower')).map((n) => n.id),
        contains(photo.id),
      );
      expect(
        repo.search(const SearchFilters(query: 'bread')).map((n) => n.id),
        contains(voice.id),
      );
      expect(repo.getById(photo.id)!.caption, isNull);
    },
  );

  test(
    'image and audio file notes use media content rather than filenames',
    () async {
      final image = insert(NoteType.file, mime: 'image/jpeg');
      final audio = insert(NoteType.file, extension: 'mp3', mime: 'audio/mpeg');
      await ai.readMediaOnDemand(image.id);
      await ai.readMediaOnDemand(audio.id);
      expect(repo.getById(image.id)!.aiSourceText, contains('flower'));
      expect(repo.getById(audio.id)!.aiSourceText, contains('bread'));
      expect(
        repo.search(const SearchFilters(query: 'flower')).map((n) => n.id),
        contains(image.id),
      );
      expect(repo.getById(audio.id)!.content, 'my-file.mp3');
    },
  );

  test(
    'failure preserves a previous result and capability off makes no request',
    () async {
      final photo = insert(NoteType.photo);
      repo.setOcrText(photo.id, 'Earlier result');
      reader.fail = true;
      expect(await ai.readMediaOnDemand(photo.id), isNull);
      expect(repo.getById(photo.id)!.ocrText, 'Earlier result');
      ai.updateCapabilities(AiCapabilities.allOff);
      expect(await ai.readMediaOnDemand(photo.id), isNull);
      expect(reader.images, 1);
    },
  );

  test(
    'a summary for an older image reading cannot overwrite a newer source',
    () async {
      final photo = insert(NoteType.photo);
      repo.setOcrText(photo.id, 'Old image details and visible writing.');
      reader.summaryPending = Completer<Summary>();
      final request = ai.summarizeOnDemand(photo.id);
      repo.setOcrText(
        photo.id,
        'A replacement image with different useful content.',
      );
      reader.summaryPending!.complete(const Summary(text: 'Old reading'));
      expect(await request, isNull);
      expect(repo.getById(photo.id)!.summaryText, isNull);
    },
  );

  for (final deleted in [false, true]) {
    test(
      'one request at a time; stale result is rejected (deleted=$deleted)',
      () async {
        final photo = insert(NoteType.photo);
        reader.pending = Completer<OCRText>();
        final first = ai.readMediaOnDemand(photo.id);
        final second = ai.readMediaOnDemand(photo.id);
        expect(reader.images, 1);
        if (deleted) {
          repo.softDelete(photo.id);
        } else {
          repo.updateImageMedia(
            photo.id,
            '${tmp.path}/replacement.jpg',
            'replacement',
          );
        }
        reader.pending!.complete(const OCRText(text: 'Old image result'));
        expect(await first, isNull);
        expect(await second, isNull);
        if (!deleted) expect(repo.getById(photo.id)!.ocrText, isNull);
      },
    );
  }

  test(
    'adding to a caption preserves body and media and appends to current caption',
    () {
      final note = insert(NoteType.text);
      expect(repo.appendCaption(note.id, 'First result'), isTrue);
      repo.setCaption(note.id, 'A concurrent edit');
      expect(repo.appendCaption(note.id, 'New result'), isTrue);
      final after = repo.getById(note.id)!;
      expect(after.caption, 'A concurrent edit\n\nNew result');
      expect(after.content, note.content);
      expect(after.mediaUri, note.mediaUri);
      expect(
        repo.search(const SearchFilters(query: 'concurrent')).map((n) => n.id),
        contains(note.id),
      );
      expect(repo.appendCaption(note.id, 'New result'), isTrue);
      expect(repo.getById(note.id)!.caption, after.caption);
      expect(repo.appendCaption(note.id, '  '), isFalse);
      repo.softDelete(note.id);
      expect(repo.appendCaption(note.id, 'Do not resurrect'), isFalse);
    },
  );

  for (final type in [
    NoteType.text,
    NoteType.photo,
    NoteType.voice,
    NoteType.file,
  ]) {
    test(
      'replace caption preserves $type and rejects a stale confirmation',
      () {
        final note = insert(type);
        repo.setCaption(note.id, 'Original caption');
        expect(
          repo.replaceCaption(
            note.id,
            'Replacement result',
            expectedCaption: 'Original caption',
          ),
          isTrue,
        );
        final replaced = repo.getById(note.id)!;
        expect(replaced.caption, 'Replacement result');
        expect(replaced.content, note.content);
        expect(replaced.mediaUri, note.mediaUri);
        expect(replaced.mediaHash, note.mediaHash);
        expect(
          repo
              .search(const SearchFilters(query: 'Replacement'))
              .map((n) => n.id),
          contains(note.id),
        );
        repo.setCaption(note.id, 'Newer manual edit');
        expect(
          repo.replaceCaption(
            note.id,
            'Do not overwrite',
            expectedCaption: 'Replacement result',
          ),
          isFalse,
        );
        expect(repo.getById(note.id)!.caption, 'Newer manual edit');
        expect(
          repo.replaceCaption(
            note.id,
            '  ',
            expectedCaption: 'Newer manual edit',
          ),
          isFalse,
        );
        repo.softDelete(note.id);
        expect(
          repo.replaceCaption(
            note.id,
            'Do not resurrect',
            expectedCaption: 'Newer manual edit',
          ),
          isFalse,
        );
      },
    );
  }
}
