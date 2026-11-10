import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/copy_feedback.dart';

/// One helper, one receipt: every copy in the app says the same word —
/// counted when it was a selection's — and no copy adds a buzz to the
/// gesture that asked for it.
///
/// (On Android 13+ the system's own clipboard preview is the receipt and
/// the banner stays down; that half is native and is not what a widget
/// test can see. What it can see is the banner that every other platform
/// gets.)
void main() {
  Future<void> pump(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onCopy,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {},
                child: const Text('copy'),
              ),
            ),
          ),
        ),
      ),
    );
    // Test the asynchronous copy-to-clipboard boundary explicitly.
    // A button's void callback does not await nexCopy, so the banner may
    // not exist when pumpAndSettle decides that there are no more frames.
    await onCopy(tester.element(find.text('copy')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
  }

  testWidgets('a plain copy says the one word', (tester) async {
    await pump(tester, (context) => nexCopy(context, 'words'));
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('a selection copy says the counted word', (tester) async {
    await pump(tester, (context) => nexCopy(context, 'a\n\nb', count: 2));
    expect(find.text('Copied 2 notes'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
  });
}
