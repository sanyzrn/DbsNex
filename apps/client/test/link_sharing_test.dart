import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/sharing.dart';
import 'package:nex_core/nex_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<Object?, Object?> shared;
  late Directory directory;
  final now = DateTime.utc(2026, 10, 18);
  final note = Note(
    id: 'link',
    type: NoteType.link,
    content: 'https://example.com/reference',
    title: 'A page title',
    caption: 'A useful reference',
    createdAt: now,
    updatedAt: now,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  setUp(() {
    directory = Directory.systemTemp.createTempSync('nex-link-share-');
    messenger.setMockMethodCallHandler(channel, (call) async {
      shared = Map<Object?, Object?>.from(call.arguments as Map);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  for (final attached in [false, true]) {
    test(
      'sharing a link ${attached ? 'with' : 'without'} a file preserves URL and caption',
      () async {
        final file = File('${directory.path}/reference.pdf')
          ..writeAsStringSync('%PDF-1.4');
        final attachment = NoteAttachment(
          id: 'file',
          noteId: note.id,
          position: 1,
          kind: AttachmentKind.file,
          mediaUri: file.path,
          mediaHash: 'hash',
          mimeType: 'application/pdf',
          createdAt: now,
          updatedAt: now,
          deviceId: 'test',
          rev: 1,
        );
        expect(
          await nexShareNote(note, attachments: attached ? [attachment] : []),
          isTrue,
        );
        expect(
          shared['text'],
          'https://example.com/reference\n\nA useful reference',
        );
        expect(shared['paths'], attached ? [file.path] : isNull);
      },
    );
  }

  test(
    'multi-note sharing preserves the link address rather than just its title',
    () async {
      await nexShareNotes([note, note]);
      expect(shared['text'], contains('https://example.com/reference'));
    },
  );
}
