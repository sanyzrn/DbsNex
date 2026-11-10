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

  testWidgets(
    'module Undo keeps its key, retry action and duration in the top capsule',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        host(
          onTap: (context) => nexShowBanner(
            context,
            message: 'Removed',
            actionLabel: 'Undo',
            actionKey: const ValueKey('module-undo'),
            duration: const Duration(seconds: 12),
            haptics: false,
            onAction: () => attempts++,
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 7));
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.getTopLeft(find.text('Removed')).dy, lessThan(150));
      await tester.tap(find.byKey(const ValueKey('module-undo')));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.text('Removed'), findsNothing);
    },
  );

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

  testWidgets('a plain banner waits behind an Undo instead of eating it', (
    tester,
  ) async {
    // The Undo a banner carries is a promise with a countdown; swallowing it
    // to say "Saved" trades something the user might still need for something
    // they can guess. The plain banner waits its turn and shows when the
    // actionable one leaves.
    var undone = false;
    await tester.pumpWidget(
      host(
        onTap: (context) {
          nexShowBanner(
            context,
            message: 'Note deleted',
            actionLabel: 'Undo',
            duration: const Duration(seconds: 30),
            haptics: false,
            onAction: () => undone = true,
          );
          nexShowBanner(context, message: 'Saved', haptics: false);
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Note deleted'), findsOneWidget);
    // Waiting, not shown: the Undo keeps its place and its countdown.
    expect(find.text('Saved'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    expect(find.text('Note deleted'), findsNothing);

    // The waiting banner takes the freed slot in the same breath.
    expect(find.text('Saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a newer waiting banner replaces an older one', (tester) async {
    // One slot, newest wins — a queue of stale receipts is worse than a
    // dropped one.
    await tester.pumpWidget(
      host(
        onTap: (context) {
          nexShowBanner(
            context,
            message: 'Note deleted',
            actionLabel: 'Undo',
            duration: const Duration(seconds: 30),
            haptics: false,
          );
          nexShowBanner(context, message: 'First', haptics: false);
          nexShowBanner(context, message: 'Second', haptics: false);
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Note deleted'), findsOneWidget);

    // Dismissing the actionable banner (its own tap) frees the slot.
    await tester.tap(find.text('Note deleted'));
    await tester.pumpAndSettle();

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('a replaced banner leaves through the edge, not by vanishing', (
    tester,
  ) async {
    // Replacement used to remove the old capsule in the same frame — its
    // reverseDuration was defined but never ran. Now the exit is an exit:
    // the old banner is still on screen a hundred milliseconds into the
    // replacement, mid-way back into the edge.
    await tester.pumpWidget(
      host(
        onTap: (context) {
          nexShowBanner(context, message: 'First', haptics: false);
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    // A second button, so the two banners are not raised in the same frame.
    await tester.pumpWidget(
      host(
        onTap: (context) {
          nexShowBanner(context, message: 'Second', haptics: false);
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('First'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('the countdown starts once the entrance is over', (tester) async {
    // The lifetime timer used to start in initState, so the entrance ate into
    // the message's own time. 'Saved' earns 2200ms of life (a five-character
    // message, at the floor), and they begin when the 360ms entrance ends —
    // at 2400ms the banner is still up, and it leaves shortly after.
    await tester.pumpWidget(
      host(
        onTap: (context) =>
            nexShowBanner(context, message: 'Saved', haptics: false),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2400));
    expect(find.text('Saved'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('holding a banner pauses its countdown', (tester) async {
    // The one person still reading it is the one holding it: the countdown
    // pauses under the finger and continues where it left off.
    await tester.pumpWidget(
      host(
        onTap: (context) =>
            nexShowBanner(context, message: 'Saved', haptics: false),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // A second into its 2200ms life.
    await tester.pump(const Duration(seconds: 1));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Saved')),
    );
    // The hold engages, and four seconds pass under the finger — longer
    // than the whole banner.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Saved'), findsOneWidget);

    await gesture.up();
    // Roughly a second of life was left when the hold began; it goes now.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
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
      isSemantics(label: 'Note deleted', isLiveRegion: true),
    );

    // And the way out is still reachable as a control, not just as text.
    // `isSemantics` rather than `matchesSemantics`: the latter asserts
    // every flag is exactly as given, so a flag Flutter adds in a later
    // release fails a case that is not about it.
    expect(
      tester.getSemantics(find.text('Undo')),
      isSemantics(label: 'Undo', isButton: true, hasTapAction: true),
    );

    handle.dispose();
  });

  testWidgets('the action button is a full-height target', (tester) async {
    // Undo is the most time-critical touch in the app and it used to sit at
    // forty pixels — under the app's own 48dp floor.
    await tester.pumpWidget(
      host(
        onTap: (context) => nexShowBanner(
          context,
          message: 'Removed',
          haptics: false,
          actionLabel: 'Undo',
          onAction: () {},
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(TextButton)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
