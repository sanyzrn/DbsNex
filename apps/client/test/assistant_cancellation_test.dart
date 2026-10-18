import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/chat_history.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_process_db.dart';

class _DelayedReads extends InProcessDb {
  _DelayedReads({required super.dbPath}) : super(deviceId: 'test');
  Completer<List<Tag>>? tags;
  Completer<List<CyclePeriod>>? periods;
  Completer<List<Note>>? timelineResult;
  bool readTags = false, readPeriods = false;
  @override
  Future<List<Tag>> listTags() {
    readTags = true;
    return tags?.future ?? super.listTags();
  }

  @override
  Future<List<CyclePeriod>> cyclePeriods() {
    readPeriods = true;
    return periods?.future ?? super.cyclePeriods();
  }

  @override
  Future<List<Note>> timeline({
    int limit = 200,
    int offset = 0,
    String? tagId,
  }) =>
      timelineResult?.future ??
      super.timeline(limit: limit, offset: offset, tagId: tagId);
}

http.Response _reply(String content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content},
      },
    ],
  }),
  200,
);

void main() {
  late Directory root;
  late _DelayedReads db;
  late NexPreferences prefs;
  late NexServices services;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('nex_cancel_review_');
    final dbPath = p.join(root.path, 'nex.sqlite');
    for (final dir in ['media', 'backups']) {
      Directory(p.join(root.path, dir)).createSync();
    }
    db = _DelayedReads(dbPath: dbPath);
    prefs = await NexPreferences.load();
    await prefs.setAiEnabled(true);
    await prefs.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
    );
    await prefs.setAiNotesContextCount(0);
    services = NexServices.forTest(
      worker: db,
      deviceId: 'test',
      preferences: prefs,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: p.join(root.path, 'media'),
      backupDir: p.join(root.path, 'backups'),
    );
  });
  tearDown(() async {
    await services.dispose();
    prefs.dispose();
    root.deleteSync(recursive: true);
  });

  Future<void> open(
    WidgetTester tester,
    http.Client client, {
    ChatThread? resume,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiChatSheet(
            preferences: prefs,
            services: services,
            history: prefs.chatHistory,
            client: client,
            resume: resume,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'Please read my tags');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  test('a late timeline reply after service teardown is ignored', () async {
    db.timelineResult = Completer<List<Note>>();
    final pending = expectLater(services.refreshTimeline(), completes);
    await services.dispose();
    db.timelineResult!.complete([]);
    await pending;
  });

  testWidgets('automatic lookup remains stoppable and cannot send after Stop', (
    tester,
  ) async {
    db.tags = Completer<List<Tag>>();
    var calls = 0;
    await open(
      tester,
      MockClient((_) async {
        calls++;
        return _reply('```nex\n{"action":"tags"}\n```');
      }),
    );
    await send(tester);
    expect(db.readTags, isTrue);
    expect(calls, 1);
    expect(find.byKey(const ValueKey('stop-chat')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stop-chat')));
    db.tags!.complete([]);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('Response stopped'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Stop during Cycle context refresh prevents an outgoing request',
    (tester) async {
      await prefs.setCycleEnabled(true);
      await prefs.setCycleAssistantAccess(true);
      db.periods = Completer<List<CyclePeriod>>();
      var calls = 0;
      await open(
        tester,
        MockClient((_) async {
          calls++;
          return _reply('This request was cancelled');
        }),
        resume: ChatThread(
          id: 'resumed',
          updatedAt: DateTime.now(),
          messages: const [
            ChatMessage(role: ChatRole.user, content: 'A previous question'),
            ChatMessage(
              role: ChatRole.user,
              content: '<<<NOTES\nCycle: not shared\nNOTES>>>',
            ),
            ChatMessage(role: ChatRole.assistant, content: 'A previous answer'),
          ],
        ),
      );
      await send(tester);
      expect(db.readPeriods, isTrue);
      expect(calls, 0);
      await tester.tap(find.byKey(const ValueKey('stop-chat')));
      db.periods!.complete([]);
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
