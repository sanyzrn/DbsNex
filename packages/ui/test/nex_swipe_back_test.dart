import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// The Cupertino back gesture only listens inside a 20-pixel strip at the
/// leading edge — the corner of a large phone a thumb has to stretch for, and
/// the same corner the back arrow already occupies. This is the gesture with
/// the rest of the page added to it.
void main() {
  Future<void> pushSecond(
    WidgetTester tester, {
    TextDirection direction = TextDirection.ltr,
    Widget? body,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        // Above the Navigator, so the transition itself sees it — the page
        // slides the way the language runs, and so does the gesture.
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  NexPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('second')),
                      body: body ?? const Center(child: Text('second body')),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(
      find.text('second body'),
      body == null ? findsOneWidget : findsNothing,
    );
  }

  testWidgets('a drag from the middle of the page goes back', (tester) async {
    await pushSecond(tester);

    // Nowhere near the edge: this is the drag the Cupertino recogniser
    // declines to see.
    await tester.fling(find.text('second body'), const Offset(300, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('second'), findsNothing);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('a drag reveals the previous page behind it', (tester) async {
    await pushSecond(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('second body')),
    );
    await gesture.moveBy(const Offset(180, 0));
    await tester.pump();

    expect(find.text('go'), findsOneWidget);
    expect(tester.getCenter(find.text('go')).dx, 400);
    expect(tester.getCenter(find.text('second body')).dx, greaterThan(400));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('under RTL, back is the other way', (tester) async {
    await pushSecond(tester, direction: TextDirection.rtl);

    // Dragging the LTR way must not pop: in Persian the page arrived from the
    // left, so it leaves to the left.
    await tester.fling(find.text('second body'), const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);

    await tester.fling(find.text('second body'), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
  });

  testWidgets('a short drag settles back instead of popping', (tester) async {
    await pushSecond(tester);

    final start = tester.getCenter(find.text('second body'));
    final gesture = await tester.startGesture(start);
    // Slowly, and well under a third of the width, so neither the distance
    // nor the velocity counts.
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('second'), findsOneWidget);
    // And it is back where it started, not left sitting 48 pixels over.
    expect(
      tester.getCenter(find.text('second body')).dx,
      closeTo(start.dx, 0.5),
    );
  });

  testWidgets('something scrollable inside the page keeps its own drag', (
    tester,
  ) async {
    await pushSecond(
      tester,
      body: SizedBox(
        height: 80,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < 30; i++)
              SizedBox(width: 100, child: Center(child: Text('chip $i'))),
          ],
        ),
      ),
    );

    await tester.fling(find.text('chip 1'), const Offset(300, 0), 1200);
    await tester.pumpAndSettle();

    // The row of chips won the arena, so the page is still here.
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('a route that refuses to pop keeps its gesture', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  NexPageRoute<void>(
                    builder: (_) => const PopScope(
                      // What a form guarding unsaved work does.
                      canPop: false,
                      child: Scaffold(body: Center(child: Text('guarded'))),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final before = tester.getCenter(find.text('guarded'));
    await tester.fling(find.text('guarded'), const Offset(300, 0), 1200);
    await tester.pumpAndSettle();

    // Still here, and — the part that was broken — back where it started
    // rather than left translated 300 pixels over with the gesture latched
    // off for the rest of the route's life.
    expect(find.text('guarded'), findsOneWidget);
    expect(tester.getCenter(find.text('guarded')).dx, closeTo(before.dx, 0.5));

    // And it still answers, which is what "latched off" would have broken.
    await tester.fling(find.text('guarded'), const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('guarded')).dx, closeTo(before.dx, 0.5));
  });
}
