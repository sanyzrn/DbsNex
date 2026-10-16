import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  final now = DateTime.utc(2026, 10, 16);
  final tag = Tag(id: 'work', name: 'Work', color: '#0084F7', createdAt: now);
  Note note({bool tagged = false, bool pinned = false}) => Note(
    id: 'note',
    type: NoteType.text,
    content: 'A note',
    createdAt: now,
    updatedAt: now,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
    tags: tagged ? [tag] : [],
    pinnedAt: pinned ? now : null,
  );
  Widget host(Note value, {bool reduced = false}) => MaterialApp(
    theme: nexLightTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
    home: Scaffold(body: NoteCard(note: value)),
  );
  final pulse = find.byKey(const ValueKey('note-marker-pulse-note'));

  testWidgets('markers are still on initial paint and ordinary rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(host(note(tagged: true, pinned: true)));
    await tester.pumpAndSettle();
    expect(pulse, findsNothing);
    await tester.pumpWidget(host(note(tagged: true, pinned: true)));
    await tester.pumpAndSettle();
    expect(pulse, findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final pin in [false, true]) {
    testWidgets(
      '${pin ? 'pin' : 'tag'} change has a bounded pulse, then rests',
      (tester) async {
        await tester.pumpWidget(host(note()));
        await tester.pumpWidget(host(note(tagged: !pin, pinned: pin)));
        await tester.pump(const Duration(milliseconds: 110));
        final scale = tester.widget<Transform>(pulse).transform.entry(0, 0);
        expect(scale, greaterThan(1));
        expect(scale, lessThanOrEqualTo(1.08));
        await tester.pumpAndSettle();
        expect(tester.widget<Transform>(pulse).transform.entry(0, 0), 1);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets('enabling reduced motion stops a pulse already running', (
    tester,
  ) async {
    await tester.pumpWidget(host(note()));
    await tester.pumpWidget(host(note(tagged: true)));
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.widget<Transform>(pulse).transform.entry(0, 0),
      greaterThan(1),
    );
    await tester.pumpWidget(host(note(tagged: true), reduced: true));
    await tester.pump();
    expect(tester.widget<Transform>(pulse).transform.entry(0, 0), 1);
    final builder = tester.widget<AnimatedBuilder>(
      find.ancestor(of: pulse, matching: find.byType(AnimatedBuilder)).first,
    );
    expect((builder.listenable as AnimationController).isAnimating, isFalse);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion adds the marker without a pulse', (tester) async {
    await tester.pumpWidget(host(note(), reduced: true));
    await tester.pumpWidget(host(note(tagged: true), reduced: true));
    await tester.pumpAndSettle();
    expect(pulse, findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
