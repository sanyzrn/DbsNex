import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/db_worker.dart';
import 'package:nex_core/nex_core.dart';

class _MediaAdapter implements AIAdapter {
  const _MediaAdapter();
  @override
  Future<OCRText>? ocr(ImageRef image) async =>
      const OCRText(text: 'A small flower in a pot.');
  @override
  Future<Transcript>? transcribe(AudioRef audio) async =>
      const Transcript(text: 'Call the bank tomorrow.');
  @override
  Future<Vector>? embed(String text) => null;
  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) => null;
  @override
  Future<Summary>? summarize(Note note) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'manual media, attachment refresh and caption append cross the real worker protocol',
    () async {
      final tmp = Directory.systemTemp.createTempSync('nex_manual_worker_');
      final worker = await NexDbWorker.spawn(
        dbPath: '${tmp.path}/nex.sqlite',
        deviceId: 'test',
        mediaDir: tmp.path,
        adapter: const _MediaAdapter(),
        capabilities: AiCapabilities.allOn,
      );
      try {
        final photo = await worker.capturePhoto(
          mediaUri: '${tmp.path}/image.jpg',
          mediaHash: 'image',
        );
        final voice = await worker.captureVoice(
          mediaUri: '${tmp.path}/clip.m4a',
          mediaHash: 'clip',
          durationMs: 100,
        );
        await worker.enrichNote(photo.id);
        await worker.enrichNote(voice.id);
        await worker.backfillEnrichment();
        expect((await worker.getById(photo.id))!.ocrText, isNull);
        expect((await worker.getById(voice.id))!.transcriptText, isNull);
        expect(
          await worker.readMediaOnDemand(photo.id),
          'A small flower in a pot.',
        );
        expect(
          await worker.readMediaOnDemand(voice.id),
          'Call the bank tomorrow.',
        );
        await worker.setCaption(photo.id, 'Keep this');
        expect(
          await worker.appendCaption(photo.id, 'A small flower in a pot.'),
          isTrue,
        );
        expect(
          (await worker.getById(photo.id))!.caption,
          'Keep this\n\nA small flower in a pot.',
        );
        final attachment = await worker.attachmentAdd(
          photo.id,
          kind: AttachmentKind.photo,
          mediaUri: '${tmp.path}/attached.jpg',
          mediaHash: 'attached',
        );
        expect(
          await worker.attachmentReadText(attachment!.id, refresh: true),
          isTrue,
        );
        expect(
          (await worker.attachmentsFor(photo.id)).single.ocrText,
          'A small flower in a pot.',
        );
      } finally {
        await worker.close();
        tmp.deleteSync(recursive: true);
      }
    },
  );
}
