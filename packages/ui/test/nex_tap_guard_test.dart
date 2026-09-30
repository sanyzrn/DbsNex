import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// W4.5: while something is open, the first tap closes it and does nothing
/// else.
void main() {
  group('NexTapGuardController', () {
    test('a tap with nothing open is the caller\'s', () {
      final guard = NexTapGuardController();
      var notified = 0;
      guard.addListener(() => notified++);
      expect(guard.claim(), isFalse);
      expect(notified, 0);
    });

    test('a tap while open closes it, once', () {
      final guard = NexTapGuardController();
      var closes = 0;
      guard.open('menu', close: () => closes++);
      expect(guard.isOpen, isTrue);
      expect(guard.claim(), isTrue);
      expect(closes, 1);
      expect(guard.isOpen, isFalse);
      expect(guard.claim(), isFalse);
      expect(closes, 1);
    });

    test('opening a second thing closes the first', () {
      final guard = NexTapGuardController();
      final closed = <String>[];
      guard
        ..open('swipe', close: () => closed.add('swipe'))
        ..open('menu', close: () => closed.add('menu'));
      expect(closed, ['swipe']);
      expect(guard.owner, 'menu');
    });

    test('closing by itself is ignored unless it is the one open', () {
      final guard = NexTapGuardController()..open('menu', close: () {});
      guard.closed('swipe');
      expect(guard.owner, 'menu');
      guard.closed('menu');
      expect(guard.isOpen, isFalse);
    });
  });

  testWidgets('a guarded control is inert while open, then works again', (
    tester,
  ) async {
    final guard = NexTapGuardController();
    var pressed = 0;
    var closes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NexTapGuard(
          controller: guard,
          child: Center(
            child: NexTapGuarded(
              child: TextButton(
                onPressed: () => pressed++,
                child: const Text('fold'),
              ),
            ),
          ),
        ),
      ),
    );

    guard.open('card', close: () => closes++);
    await tester.pump();
    await tester.tap(find.text('fold'));
    await tester.pump();
    expect(closes, 1);
    expect(pressed, 0, reason: 'the tap that closes presses nothing');

    await tester.tap(find.text('fold'));
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('a list under guarded rows still scrolls while open', (
    tester,
  ) async {
    final guard = NexTapGuardController()..open('card', close: () {});
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NexTapGuard(
            controller: guard,
            child: ListView(
              controller: scroll,
              children: [
                for (var i = 0; i < 40; i++)
                  NexTapGuarded(
                    child: ListTile(title: Text('row $i'), onTap: () {}),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.text('row 3'), const Offset(0, -300));
    await tester.pump();
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('with no guard in scope the child is left as it is', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: NexTapGuarded(
            child: TextButton(
              onPressed: () => pressed++,
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    expect(pressed, 1);
  });
}
