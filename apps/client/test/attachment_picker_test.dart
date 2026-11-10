import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/os_capture_bridge.dart';
import 'package:nex_client/widgets/attachment_picker.dart';
import 'package:nex_client/widgets/nex_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/file_selector');

  testWidgets(
    '500 MiB boundary accepts without reading and refusal shows a banner',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('nex-file-limit-');
      addTearDown(() => dir.deleteSync(recursive: true));
      addTearDown(nexHideBanner);
      final file = File('${dir.path}/large.bin');
      final handle = await file.open(mode: FileMode.write);
      // Sparse length, no 500 MiB allocation or transfer.
      await handle.truncate(500 * 1024 * 1024);
      await handle.close();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => [file.path]);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final accepted = await OsCaptureBridge.pickFile();
      expect(accepted?.path, file.path);
      final larger = await file.open(mode: FileMode.append);
      await larger.truncate(500 * 1024 * 1024 + 1);
      await larger.close();
      Future<PickedOsFile?>? selection;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  selection = nexPickAttachment(context);
                },
                child: const Text('pick'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pick'));
      expect(await tester.runAsync(() => selection!), isNull);
      await tester.pumpAndSettle();
      expect(find.textContaining('500.0 MB'), findsOneWidget);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await OsCaptureBridge.pickFile(), isNull);
    },
  );
}
