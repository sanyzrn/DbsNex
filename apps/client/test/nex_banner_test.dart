import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/widgets/nex_banner.dart';

/// Messages arrive from the top now rather than as a bottom SnackBar. The
/// position is the point: the bottom of the screen is where this app's own
/// controls live, so a message landing there covers the thing you were about
/// to press.
void main() {
  Widget host({required void Function(BuildContext) onTap}) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onTap(context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );

  tearDown(nexHideBanner);

  testWidgets('a banner comes in from the top and leaves on its own', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onTap: (context) =>
            nexShowBanner(context, message: 'Saved', haptics: false),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Saved'), findsOneWidget);
    // Above the halfway line, which a SnackBar never is.
    final rect = tester.getRect(find.text('Saved'));
    expect(rect.center.dy, lessThan(tester.view.physicalSize.height / 4));

    // It goes without being dismissed — nothing here has to be acknowledged.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('tapping a banner dismisses it early', (tester) async {
    await tester.pumpWidget(
      host(
        onTap: (context) =>
            nexShowBanner(context, message: 'Copied', haptics: false),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsOneWidget);

    await tester.tap(find.text('Copied'));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('an action runs and takes the banner with it', (tester) async {
    var undone = false;
    await tester.pumpWidget(
      host(
        onTap: (context) => nexShowBanner(
          context,
          message: 'Note deleted',
          haptics: false,
          actionLabel: 'Undo',
          onAction: () => undone = true,
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(undone, isTrue);
    expect(find.text('Note deleted'), findsNothing);
  });

  testWidgets('a second message replaces the first rather than queueing', (
    tester,
  ) async {
    // A queue would mean the message you are reading is about something you
    // did several actions ago.
    await tester.pumpWidget(
      host(
        onTap: (context) {
          nexShowBanner(context, message: 'First', haptics: false);
          nexShowBanner(context, message: 'Second', haptics: false);
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('an action gets longer to be reached than a confirmation does', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onTap: (context) => nexShowBanner(
          context,
          message: 'Note deleted',
          haptics: false,
          actionLabel: 'Undo',
          onAction: () {},
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Past the plain 3.4s life, and still there — noticing a delete, deciding
    // against it and reaching Undo takes longer than reading "Saved".
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Note deleted'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Note deleted'), findsNothing);
  });

  testWidgets('a banner announces itself to a screen reader', (tester) async {
    // It used to be a `ScaffoldMessenger` snack bar, which announces itself.
    // Moving it onto a raw `OverlayEntry` for the look dropped that silently,
    // and nothing failed — a screen-reader user simply stopped being told
    // anything. The delete banner is the case that hurts: the only way back
    // from a swipe-delete is an Undo that lives here for six seconds.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        onTap: (context) => nexShowBanner(
          context,
          message: 'Note deleted',
          haptics: false,
          actionLabel: 'Undo',
          onAction: () {},
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // `liveRegion` is what makes the platform read a node that appeared
    // without anyone moving focus to it — which is the whole situation.
    expect(
      tester.getSemantics(find.text('Note deleted')),
      containsSemantics(label: 'Note deleted', isLiveRegion: true),
    );

    // And the way out is still reachable as a control, not just as text.
    // `containsSemantics` rather than `matchesSemantics`: the latter asserts
    // every flag is exactly as given, so a flag Flutter adds in a later
    // release fails a case that is not about it.
    expect(
      tester.getSemantics(find.text('Undo')),
      containsSemantics(label: 'Undo', isButton: true, hasTapAction: true),
    );

    handle.dispose();
  });
}
