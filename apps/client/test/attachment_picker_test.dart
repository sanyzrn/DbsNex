import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/os_capture_bridge.dart';
import 'package:nex_client/widgets/attachment_picker.dart';
import 'package:nex_client/widgets/nex_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '500 MiB boundary accepts without reading and refusal shows a banner',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('nex-file-limit-');
      addTearDown(() => dir.deleteSync(recursive: true));
      addTearDown(nexHideBanner);
      final file = File('${dir.path}/large.bin');
      final handle = file.openSync(mode: FileMode.write);
      // Sparse length, no 500 MiB allocation or transfer. File operations
      // must not await real I/O inside Flutter's fake-async widget zone.
      handle.truncateSync(500 * 1024 * 1024);
      handle.closeSync();
      final accepted = await tester.runAsync(
        () => OsCaptureBridge.pickFile(
          selectFile: () async => XFile(file.path),
        ),
      );
      expect(accepted?.path, file.path);
      final larger = file.openSync(mode: FileMode.append);
      larger.truncateSync(500 * 1024 * 1024 + 1);
      larger.closeSync();
      Future<PickedOsFile?>? selection;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  selection = nexPickAttachment(
                    context,
                    pickFile: () => OsCaptureBridge.pickFile(
                      selectFile: () async => XFile(file.path),
                    ),
                  );
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
      expect(
        await tester.runAsync(
          () => OsCaptureBridge.pickFile(selectFile: () async => null),
        ),
        isNull,
      );
    },
  );
}
