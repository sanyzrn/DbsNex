import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/ai_provider.dart';
import 'package:nex_client/platform/disclosure_log.dart';
import 'package:nex_client/screens/disclosures_screen.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;

import 'support/nex_harness.dart';

/// W3.2: every request to a provider is written down, on the phone only.
/// Lets the screen's real file IO finish; fake time alone never completes it.
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nex_disclosures_');
    NexDisclosureLog.configure(dir.path);
  });
  tearDown(() {
    NexDisclosureLog.configure(p.join(dir.path, 'gone'));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Note note(String id, String content) {
    final now = DateTime.now().toUtc();
    return Note(
      id: id,
      type: NoteType.text,
      content: content,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  CloudAIAdapter adapter({List<http.BaseRequest>? seen}) => CloudAIAdapter(
    config: const AiProviderConfig(
      provider: AiProvider.openai,
      apiKey: 'sk-secret',
    ),
    client: MockClient((request) async {
      seen?.add(request);
      if (request.url.path.endsWith('/audio/transcriptions')) {
        return http.Response(jsonEncode({'text': 'hello'}), 200);
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'Work, Ideas'},
            },
          ],
        }),
        200,
      );
    }),
  );

  test('a tag suggestion records its provider, purpose and note', () async {
    await adapter().suggestTags(note('n1', 'a note about work'))!;
    final entries = await NexDisclosureLog.read();
    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.provider, AiProvider.openai.label);
    expect(entry.host, 'api.openai.com');
    expect(entry.purpose, DisclosurePurpose.tags);
    expect(entry.content, {DisclosureContent.text});
    expect(entry.noteIds, ['n1']);
    expect(entry.bytes, greaterThan(0));
  });

  test('the key, the path and the content never reach the record', () async {
    await adapter().suggestTags(note('n1', 'my bank pin is 4321'))!;
    final raw = File(
      p.join(dir.path, NexDisclosureLog.fileName),
    ).readAsStringSync();
    expect(raw, isNot(contains('sk-secret')));
    expect(raw, isNot(contains('4321')));
    expect(raw, isNot(contains('/v1/')));
  });

  test('a question with a photo says an image went with it', () async {
    await NexDisclosureLog.about(
      () => adapter().chat(
        [const ChatMessage(role: ChatRole.user, content: 'what is this?')],
        options: const AiChatOptions(
          attachments: [
            NexChatAttachment(bytes: [1, 2, 3], mimeType: 'image/jpeg'),
          ],
        ),
      ),
      notes: ['n7', 'n8'],
    );
    final entry = (await NexDisclosureLog.read()).single;
    expect(entry.purpose, DisclosurePurpose.chat);
    expect(entry.content, containsAll([DisclosureContent.image]));
    expect(entry.noteIds, ['n7', 'n8']);
  });

  test('a transcription is recorded as audio from the recording', () async {
    await adapter().transcribe(
      AudioRef(
        mediaUri: '/data/media/voice-1.m4a',
        bytes: Uint8List.fromList([0, 1, 2, 3]),
      ),
    )!;
    final entry = (await NexDisclosureLog.read()).single;
    expect(entry.purpose, DisclosurePurpose.transcription);
    expect(entry.content, {DisclosureContent.audio});
    expect(entry.media, 'voice-1.m4a');
  });

  test('newest first, a torn line skipped, and cleared on request', () async {
    await adapter().suggestTags(note('a', 'first'))!;
    File(
      p.join(dir.path, NexDisclosureLog.fileName),
    ).writeAsStringSync('{"at": "2026-', mode: FileMode.append);
    File(
      p.join(dir.path, NexDisclosureLog.fileName),
    ).writeAsStringSync('\n', mode: FileMode.append);
    await adapter().summarizeText('second, rather longer than its summary');
    final entries = await NexDisclosureLog.read();
    expect(entries.map((e) => e.purpose), [
      DisclosurePurpose.summary,
      DisclosurePurpose.tags,
    ]);
    await NexDisclosureLog.clear();
    expect(await NexDisclosureLog.read(), isEmpty);
  });

  test('the record keeps only the newest entries', () async {
    final file = File(p.join(dir.path, NexDisclosureLog.fileName));
    final line = jsonEncode(
      DisclosureEntry(
        at: DateTime.utc(2026),
        provider: 'X',
        host: 'x.test',
        purpose: DisclosurePurpose.other,
        content: const {DisclosureContent.text},
        bytes: 1,
      ).toJson(),
    );
    file.writeAsStringSync(
      '${List.filled(NexDisclosureLog.keep * 2, line).join('\n')}\n',
    );
    expect(await NexDisclosureLog.read(), hasLength(NexDisclosureLog.keep));
    expect(
      file.readAsLinesSync().where((l) => l.isNotEmpty),
      hasLength(NexDisclosureLog.keep),
    );
  });

  testWidgets('the screen lists what was sent and clears it', (tester) async {
    final harness = await NexTestHarness.create();
    addTearDown(harness.dispose);
    await tester.runAsync(() async {
      await adapter().suggestTags(note('n1', 'a note'))!;
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DisclosuresScreen(services: harness.services),
      ),
    );
    await _settleIo(tester);
    expect(find.text('Tag suggestions'), findsOneWidget);
    expect(find.textContaining('api.openai.com'), findsOneWidget);
    expect(find.textContaining('From 1 note'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear record'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Clear record'));
    await _settleIo(tester);
    expect(find.text('Nothing has left this device.'), findsOneWidget);
  });
}
