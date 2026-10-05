import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/sharing.dart';
import 'package:nex_client/widgets/rename_file_dialog.dart';
import 'package:nex_core/nex_core.dart';

Note _note(
  NoteType type, {
  String? content,
  String? mediaUri,
  String? caption,
  String? title,
  String? mimeType,
}) => Note(
  id: 'n',
  type: type,
  content: content,
  mediaUri: mediaUri,
  caption: caption,
  title: title,
  mimeType: mimeType,
  createdAt: DateTime(2026, 10, 5, 9, 7),
  updatedAt: DateTime(2026, 10, 5, 9, 7),
  deviceId: 'd',
  rev: 1,
  syncState: SyncState.synced,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what a note saves as', () {
    test('a file note saves its file under its own name', () {
      final t = nexSaveTargetFor(
        _note(
          NoteType.file,
          content: 'قرارداد اجاره.pdf',
          mediaUri: '/media/abc.pdf',
          mimeType: 'application/pdf',
        ),
      )!;
      expect(t.name, 'قرارداد اجاره.pdf');
      expect(t.sourcePath, '/media/abc.pdf');
      expect(t.mimeType, 'application/pdf');
    });

    test('a photo saves under its caption, or the moment it was taken', () {
      expect(
        nexSaveTargetFor(
          _note(NoteType.photo, mediaUri: '/m/x.jpg', caption: 'رسید خرید'),
        )!.name,
        'رسید خرید.jpg',
      );
      final plain = nexSaveTargetFor(
        _note(NoteType.photo, mediaUri: '/m/x.jpg'),
      )!;
      expect(plain.name, 'Nex photo 2026-10-05 0907.jpg');
      expect(plain.mimeType, 'image/jpeg');
    });

    test('a text note saves as Markdown named after its first line', () {
      final t = nexSaveTargetFor(
        _note(NoteType.text, content: '# Trip plan\n- tickets'),
      )!;
      expect(t.name, 'Trip plan.md');
      expect(t.text, '# Trip plan\n- tickets\n');
      expect(t.sourcePath, isNull);
    });

    test('a link saves as a Markdown link', () {
      final t = nexSaveTargetFor(
        _note(
          NoteType.link,
          content: 'https://example.com/a',
          title: 'Example',
          caption: 'read later',
        ),
      )!;
      expect(t.text, '[Example](https://example.com/a)\n\nread later');
    });

    test('an empty note has nothing to save', () {
      expect(nexSaveTargetFor(_note(NoteType.text, content: '  ')), isNull);
    });
  });

  test('on Android the system save dialog gets the file, name and type, '
      'and its answer is reported', () async {
    const channel = MethodChannel('nex/os_capture');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    var answer = 'saved';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<SaveOutcome> save() => nexSaveFileToDevice(
      '/tmp/x.md',
      name: 'x.md',
      mimeType: 'text/markdown',
      android: true,
    );
    expect(await save(), SaveOutcome.saved);
    expect(calls.single.method, 'saveToDevice');
    expect(calls.single.arguments, {
      'path': '/tmp/x.md',
      'name': 'x.md',
      'mimeType': 'text/markdown',
    });
    answer = 'cancelled';
    expect(await save(), SaveOutcome.cancelled);
    answer = 'failed';
    expect(await save(), SaveOutcome.failed);
  });

  testWidgets('rename keeps the extension and refuses forbidden names', (
    tester,
  ) async {
    String? result = 'untouched';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await nexAskFileName(context, current: 'note.md'),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('rename-file-field'));
    expect(find.text('.md'), findsOneWidget);
    await tester.enterText(field, 'a/b');
    await tester.pump();
    expect(find.textContaining("can't contain"), findsOneWidget);
    final rename = find.widgetWithText(TextButton, 'Rename');
    expect(tester.widget<TextButton>(rename).onPressed, isNull);

    await tester.enterText(field, 'Weekly plan');
    await tester.pump();
    await tester.tap(rename);
    await tester.pumpAndSettle();
    expect(result, 'Weekly plan.md');
  });
}
