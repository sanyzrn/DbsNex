import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/widgets/persian_date_picker.dart';
import 'package:nex_client/widgets/note_editor_sheet.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/display_date.dart';
import 'package:nex_client/platform/editor_drafts.dart';
import 'package:nex_client/platform/full_backup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'settings restore and undo journal retain device identity and remove newer credentials',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await NexPreferences.load();
      final id = await prefs.stableDeviceId();
      await prefs.setDisplayName('Original');
      final old = prefs.backupSettings();
      await prefs.beginRestoreRecovery('/backups/safety.nexbak');
      await prefs.setDisplayName('Changed');
      await prefs.setAiProvider(
        const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'private-key',
        ),
      );
      final pending = await prefs.pendingRestoreRecovery();
      expect(pending?['settings'], old);
      await prefs.restoreSettings(
        Map<String, dynamic>.from(pending!['settings'] as Map),
      );
      expect(prefs.displayName, 'Original');
      expect(prefs.configFor(AiProvider.openai).apiKey, isEmpty);
      expect(await prefs.stableDeviceId(), id);
      expect(await prefs.pendingRestoreRecovery(), isNotNull);
      await prefs.finishRestoreRecovery();
      expect(await prefs.pendingRestoreRecovery(), isNull);
    },
  );

  testWidgets(
    'birthday calendar chooses the Persian date and returns the civil day',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PersianDatePicker(
            initial: DateTime(2026, 3, 22),
            first: DateTime(1900),
            last: DateTime(2100),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('فروردین'), findsOneWidget);
      expect(find.text('۱۴۰۵/۰۱/۰۲'), findsOneWidget);
      await tester.tap(find.text('۱').last);
      await tester.pump();
      expect(find.text('۱۴۰۵/۰۱/۰۱'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'text editor recovers after its widget is destroyed without save',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await NexPreferences.load();
      final root = Directory.systemTemp.createTempSync('nex-editor-test-');
      addTearDown(() => root.deleteSync(recursive: true));
      prefs.editorDrafts = EditorDrafts(root.path);
      Widget editor() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteEditorSheet(
            initial: 'Original',
            preferences: prefs,
            draftKey: 'note-one',
          ),
        ),
      );
      await tester.pumpWidget(editor());
      await tester.enterText(find.byType(TextField), 'Unfinished فارسی');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(editor());
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Unfinished فارسی',
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('Persian calendar round trips every day across two centuries', () {
    for (
      var date = DateTime.utc(1900);
      date.year <= 2100;
      date = date.add(const Duration(days: 1))
    ) {
      final solar = nexPersianDate(date);
      final civil = nexGregorianDate(solar.year, solar.month, solar.day);
      expect(
        (civil.year, civil.month, civil.day),
        (date.year, date.month, date.day),
      );
    }
    expect(nexPersianMonthDays(1403, 12), 30);
    expect(() => nexGregorianDate(1404, 12, 30), throwsRangeError);
  });

  test('editor drafts survive recreation and discard is scoped', () {
    final root = Directory.systemTemp.createTempSync('nex-drafts-');
    addTearDown(() => root.deleteSync(recursive: true));
    EditorDrafts(root.path).write('note-one', {'text': 'فارسی gpt'});
    EditorDrafts(root.path).write('note-two', {'text': 'another'});
    final restored = EditorDrafts(root.path);
    expect(restored.read('note-one')?['text'], 'فارسی gpt');
    restored.clear('note-one');
    expect(restored.read('note-one'), isNull);
    expect(restored.read('note-two')?['text'], 'another');
  });

  test(
    'complete backup encrypts settings, rejects wrong key and extracts library',
    () {
      final root = Directory.systemTemp.createTempSync('nex-full-');
      addTearDown(() => root.deleteSync(recursive: true));
      final library = File('${root.path}/library')
        ..writeAsStringSync('library-fixture');
      final output = '${root.path}/backup.nexfull';
      final key = FullBackup.newKey();
      final settings = {
        'version': 1,
        'preferences': {'profile.name': 'Persian'},
        'credentials': {'provider': 'secret-fixture-123'},
      };
      FullBackup.create(
        library: library.path,
        output: output,
        settings: settings,
        key: key,
      );
      final archive = ZipDecoder().decodeBytes(File(output).readAsBytesSync());
      final encrypted = archive.findFile('settings.aes.zip')!.content;
      expect(latin1.decode(encrypted), isNot(contains('secret-fixture-123')));
      expect(
        () => FullBackup.unpack(
          output,
          '${root.path}/wrong',
          FullBackup.newKey(),
          modelHash: 'unused',
          modelBytes: 0,
        ),
        throwsA(anything),
      );
      expect(Directory('${root.path}/wrong').existsSync(), isFalse);
      final restored = FullBackup.unpack(
        output,
        '${root.path}/restored',
        key,
        modelHash: 'unused',
        modelBytes: 0,
      );
      expect(restored, settings);
      expect(FullBackup.modelHashOf(output), isNull);
      expect(
        File('${root.path}/restored/library.nexbak').readAsStringSync(),
        'library-fixture',
      );
    },
  );
  test(
    'complete backup restores model bytes and rejects a checksum mismatch',
    () {
      final root = Directory.systemTemp.createTempSync('nex-full-model-');
      addTearDown(() => root.deleteSync(recursive: true));
      final library = File('${root.path}/library')
        ..writeAsStringSync('library');
      final model = File('${root.path}/model')
        ..writeAsBytesSync(List.generate(1024, (i) => i % 256));
      final original = model.readAsBytesSync();
      final hash = sha256.convert(original).toString();
      final key = FullBackup.newKey();
      void create(String output) => FullBackup.create(
        library: library.path,
        output: output,
        key: key,
        settings: {
          'version': 1,
          'preferences': <String, dynamic>{},
          'credentials': <String, String>{},
        },
        model: model.path,
        modelHash: hash,
      );
      final output = '${root.path}/complete.nexfull';
      create(output);
      // The header says which model is inside, so a restore knows which of
      // the offered models to check it against.
      expect(FullBackup.modelHashOf(output), hash);
      FullBackup.unpack(
        output,
        '${root.path}/restored',
        key,
        modelHash: hash,
        modelBytes: original.length,
      );
      expect(
        File('${root.path}/restored/model.litertlm').readAsBytesSync(),
        original,
      );
      model.writeAsBytesSync(List.filled(original.length, 0));
      final damaged = '${root.path}/damaged.nexfull';
      create(damaged);
      expect(
        () => FullBackup.unpack(
          damaged,
          '${root.path}/rejected',
          key,
          modelHash: hash,
          modelBytes: original.length,
        ),
        throwsFormatException,
      );
    },
  );
}
