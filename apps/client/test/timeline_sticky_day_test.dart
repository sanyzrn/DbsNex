import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_data/nex_data.dart';

import 'support/nex_harness.dart';

/// W7.1: scrolling through older notes, the day of the card passing under
/// the filter row is named there.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_sticky_day_');
    final db = NexDatabase.open(harness.dbPath);
    // Sixty notes, one every eight hours, all well in the past.
    final start = DateTime.now().toUtc().subtract(const Duration(days: 60));
    db.db.execute('BEGIN IMMEDIATE');
    for (var i = 0; i < 60; i++) {
      final at = start.add(Duration(hours: i * 8)).toIso8601String();
      db.db.execute(
        'INSERT INTO notes (id, type, content, created_at, updated_at, '
        "device_id, rev, sync_state) VALUES (?, 'text', ?, ?, ?, 't', 1, "
        "'synced')",
        ['n$i', 'note number $i', at, at],
      );
    }
    db.db.execute('COMMIT');
    db.close();
    await harness.services.refreshTimeline();
  });

  tearDown(() => harness.dispose());

  String? shown(WidgetTester tester) {
    final text = find.descendant(
      of: find.byType(TimelineStickyDay),
      matching: find.byType(Text),
    );
    if (text.evaluate().isEmpty) return null;
    final value = tester.widget<Text>(text.first).data;
    final opacity = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(TimelineStickyDay),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    return opacity.opacity == 0 ? null : value;
  }

  testWidgets('the day appears once the list has moved, and follows it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    expect(shown(tester), isNull, reason: 'at the top the headings say it');

    final list = find.byType(CustomScrollView);
    await tester.drag(list, const Offset(0, -900));
    await tester.pumpAndSettle();
    final first = shown(tester);
    expect(first, isNotNull);
    expect(first, matches(RegExp(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), \d{4}/')));

    await tester.drag(list, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(shown(tester), isNot(first), reason: 'an older day further down');

    await tester.drag(list, const Offset(0, 8000));
    await tester.pumpAndSettle();
    expect(shown(tester), isNull, reason: 'back at the top');
  });
}
