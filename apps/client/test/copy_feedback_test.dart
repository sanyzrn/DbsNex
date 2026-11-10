import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/copy_feedback.dart';
import 'package:nex_client/widgets/nex_banner.dart';

/// One helper, one receipt: every copy in the app says the same word —
/// counted when it was a selection's — and no copy adds a buzz to the
/// gesture that asked for it.
///
/// (On Android 13+ the system's own clipboard preview is the receipt and
/// the banner stays down; that half is native and is not what a widget
/// test can see. What it can see is the banner that every other platform
/// gets.)
void main() {
  tearDown(nexHideBanner);

  Future<List<String>> pump(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onCopy,
  ) async {
    final copied = <String>[];
    // A widget test has no native clipboard to answer this platform call.
    // Acknowledge writes so nexCopy can finish and show its banner.
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    late Future<void> copyComplete;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  copyComplete = onCopy(context);
                },
                child: const Text('copy'),
              ),
            ),
          ),
        ),
      ),
    );
    // Exercise the button and await its clipboard write before inspecting
    // the banner. pumpAndSettle alone can finish before the async callback.
    await tester.tap(find.text('copy'));
    await tester.pump();
    await copyComplete;
    await tester.pump(const Duration(milliseconds: 750));
    return copied;
  }

  testWidgets('a plain copy says the one word', (tester) async {
    final copied = await pump(tester, (context) => nexCopy(context, 'words'));
    expect(copied, ['words']);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('a selection copy says the counted word', (tester) async {
    final copied = await pump(
      tester,
      (context) => nexCopy(context, 'a\n\nb', count: 2),
    );
    expect(copied, ['a\n\nb']);
    expect(find.text('Copied 2 notes'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
  });
}
