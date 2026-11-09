import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/nex_dialog.dart';
import 'package:nex_client/widgets/recording_sheet.dart';

/// The recording sheet is the one sheet whose dismissal used to be silent
/// data loss: the system back gesture popped it straight out from under
/// `dismissible: false`, the opener read a null result as "not kept", and
/// the temp folder — minutes of speech — went with it. Back now keeps the
/// recording, the same answer Stop gives; Discard stays a labelled button.
///
/// Fixed pumps rather than `pumpAndSettle`: the sheet's elapsed-time
/// ticker repaints every 200ms for as long as it is up, so there is never a
/// settled frame while it is open.
void main() {
  testWidgets('the system back gesture keeps the recording', (tester) async {
    bool? kept;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  kept = await nexShowSheet<bool>(
                    context: context,
                    dismissible: false,
                    builder: (_) => RecordingSheet(
                      recorder: _SilentRecorder(),
                    ),
                  );
                },
                child: const Text('record'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('record'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(RecordingSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(RecordingSheet), findsNothing);
    // Kept, not discarded: the opener attaches what the microphone caught.
    expect(kept, isTrue, reason: 'back answers what Stop answers');
  });

  testWidgets('Discard still discards, as a labelled decision', (tester) async {
    bool? kept;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  kept = await nexShowSheet<bool>(
                    context: context,
                    dismissible: false,
                    builder: (_) => RecordingSheet(
                      recorder: _SilentRecorder(),
                    ),
                  );
                },
                child: const Text('record'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('record'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(RecordingSheet), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(RecordingSheet), findsNothing);
    expect(kept, isFalse);
  });

  testWidgets('Stop still keeps, and closes the sheet', (tester) async {
    bool? kept;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  kept = await nexShowSheet<bool>(
                    context: context,
                    dismissible: false,
                    builder: (_) => RecordingSheet(
                      recorder: _SilentRecorder(),
                    ),
                  );
                },
                child: const Text('record'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('record'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(RecordingSheet), findsOneWidget);

    await tester.tap(find.text('Stop recording'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(RecordingSheet), findsNothing);
    expect(kept, isTrue);
  });
}

/// The sheet only listens for amplitude while it is up, so a recorder with
/// no platform behind it is enough to drive it.
class _SilentRecorder extends AudioRecorder {
  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      const Stream.empty();
}
