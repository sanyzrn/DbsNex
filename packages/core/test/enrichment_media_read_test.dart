import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// Reading a photo's words or a clip's speech must not read a file whole
/// into the worker's heap just for the provider to refuse it: the share
/// limit admits files no provider will take, and the bytes used to be read
/// before anything had said no.
void main() {
  // A repository is required by the constructor but never touched by the
  // media reads; noSuchMethod keeps the fixture to one line.
  NoteRepository repo() => _UnusedRepository();

  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('nex_media_read_'));
  tearDown(() => root.deleteSync(recursive: true));

  File write(String name, int length) {
    final file = File('${root.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(List.filled(length, 1));
    return file;
  }

  test('a photo under the eager cap is read once, up front', () async {
    final adapter = _RecordingAdapter();
    final service = EnrichmentService(
      repo: repo(),
      adapter: adapter,
      capabilities: const AiCapabilities(ocr: true),
    );
    final photo = write('small.jpg', 1024);

    await service.readImage(mediaUri: photo.path, mediaHash: 'h');

    final seen = adapter.images.single;
    expect(seen.mediaUri, photo.path);
    expect(seen.mediaHash, 'h');
    expect(seen.bytes, isNotNull);
    expect(seen.bytes!.length, 1024);
  });

  test(
    'a photo over the eager cap is handed over by path, not by bytes',
    () async {
      final adapter = _RecordingAdapter();
      final service = EnrichmentService(
        repo: repo(),
        adapter: adapter,
        capabilities: const AiCapabilities(ocr: true),
      );
      final photo = write('huge.jpg', EnrichmentService.maxEagerMediaBytes + 1);

      await service.readImage(mediaUri: photo.path);

      final seen = adapter.images.single;
      expect(seen.mediaUri, photo.path);
      // Null is the adapter's own cue to stat and read — and to refuse on
      // its own ceiling without the read ever happening.
      expect(seen.bytes, isNull);
    },
  );

  test('an audio file over the eager cap is handed over by path too', () async {
    final adapter = _RecordingAdapter();
    final service = EnrichmentService(
      repo: repo(),
      adapter: adapter,
      capabilities: const AiCapabilities(transcription: true),
    );
    final clip = write('long.m4a', EnrichmentService.maxEagerMediaBytes + 512);

    await service.transcribeAudio(mediaUri: clip.path);

    final seen = adapter.clips.single;
    expect(seen.mediaUri, clip.path);
    expect(seen.bytes, isNull);
  });

  test('a missing file is a path and no bytes, not a thrown read', () async {
    final adapter = _RecordingAdapter();
    final service = EnrichmentService(
      repo: repo(),
      adapter: adapter,
      capabilities: const AiCapabilities(ocr: true),
    );

    await service.readImage(
      mediaUri: '${root.path}${Platform.pathSeparator}nope.jpg',
    );

    final seen = adapter.images.single;
    expect(seen.bytes, isNull);
  });

  test(
    'the words the adapter answers are trimmed and passed through',
    () async {
      final adapter = _RecordingAdapter(ocrText: '  the words  ');
      final service = EnrichmentService(
        repo: repo(),
        adapter: adapter,
        capabilities: const AiCapabilities(ocr: true),
      );
      final photo = write('receipt.jpg', 8);

      expect(await service.readImage(mediaUri: photo.path), 'the words');
    },
  );
}

class _UnusedRepository implements NoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('the media reads never touch the repository');
}

class _RecordingAdapter implements AIAdapter {
  _RecordingAdapter({this.ocrText = 'words'});

  final String ocrText;
  final List<ImageRef> images = [];
  final List<AudioRef> clips = [];

  @override
  Future<OCRText>? ocr(ImageRef image) {
    images.add(image);
    return Future.value(OCRText(text: ocrText));
  }

  @override
  Future<Transcript>? transcribe(AudioRef audio) {
    clips.add(audio);
    return Future.value(const Transcript(text: 'said'));
  }

  @override
  Future<Vector>? embed(String text) => null;

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) => null;

  @override
  Future<Summary>? summarize(Note note) => null;
}
