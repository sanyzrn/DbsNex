import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/nex_shelf.dart';
import 'package:nex_client/widgets/tips/home_tip.dart';
import 'package:nex_client/widgets/tips/nex_tips.dart';
import 'package:nex_client/widgets/tips/tip_schedule.dart';
import 'package:nex_core/nex_core.dart';

import '../support/nex_harness.dart';

/// 2.8.4: tips on the home screen, rare and in step with the person.
void main() {
  late NexTestHarness h;
  setUp(() async => h = await NexTestHarness.create(name: 'nex_tips_'));
  tearDown(() => h.dispose());

  List<Note> notes(int count) => [
    for (var i = 0; i < count; i++)
      Note(
        id: 'n$i',
        type: NoteType.text,
        content: 'note $i',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        deviceId: 'd',
        rev: 1,
        syncState: SyncState.pending,
      ),
  ];

  NexTip tip(
    String id, {
    bool fresh = false,
    bool Function(NexTipContext)? when,
  }) => NexTip(
    id: id,
    icon: Icons.lightbulb_outline,
    hue: NexHue.sky,
    title: (_) => 'Title $id',
    body: (_) => 'Body $id',
    fresh: fresh,
    when: when,
  );

  final day1 = DateTime(2026, 11, 17, 10);
  final day2 = DateTime(2026, 11, 18, 10);

  (NexTip?, NexTipState) pick(
    NexTipState state,
    DateTime now, {
    int count = 5,
    List<NexTip>? tips,
  }) => NexTipSchedule.pick(
    tips: tips ?? [tip('a'), tip('b'), tip('c')],
    state: state,
    context: NexTipContext(notes: notes(count), preferences: h.preferences),
    now: now,
  );

  test('a quiet start: nothing on the first day or before three notes', () {
    final (first, state) = pick(const NexTipState(), day1);
    expect(first, isNull);
    expect(state.firstSeenAt, day1);
    expect(pick(state, day2, count: 2).$1, isNull);
    expect(pick(state, day2).$1, isNotNull);
  });

  test('one stays up until closed, then a rest; never at night', () {
    final start = NexTipState(firstSeenAt: day1);
    final (shown, up) = pick(start, day2);
    expect(shown, isNotNull);
    // Same tip on the next look, the same day.
    expect(pick(up, day2.add(const Duration(hours: 2))).$1?.id, shown!.id);
    final closed = NexTipSchedule.closed(up, now: day2, notes: 5);
    expect(pick(closed, day2.add(const Duration(hours: 4))).$1, isNull);
    // A day later, and closed once without the button: two days' rest.
    expect(pick(closed, day2.add(const Duration(hours: 25))).$1, isNull);
    final later = day2.add(const Duration(days: 2, hours: 1));
    expect(pick(closed, later).$1, isNotNull);
    expect(pick(closed, DateTime(2026, 11, 21, 23)).$1, isNull);
    expect(pick(closed, later).$1?.id, isNot(shown.id));
  });

  test('writing brings the next one sooner, never within three hours', () {
    final up = pick(NexTipState(firstSeenAt: day1), day2).$2;
    final closed = NexTipSchedule.closed(up, now: day2, notes: 5, acted: true);
    expect(closed.ignored, 0);
    expect(
      pick(closed, day2.add(const Duration(hours: 2)), count: 12).$1,
      isNull,
    );
    expect(
      pick(closed, day2.add(const Duration(hours: 4)), count: 10).$1,
      isNotNull,
    );
    expect(
      pick(closed, day2.add(const Duration(hours: 4)), count: 9).$1,
      isNull,
    );
  });

  test('each once; a tip that no longer fits leaves; state survives JSON', () {
    var state = NexTipState(firstSeenAt: day1);
    final seen = <String>{};
    var now = day2;
    for (var i = 0; i < 3; i++) {
      final (t, s) = pick(state, now);
      seen.add(t!.id);
      state = NexTipSchedule.closed(s, now: now, notes: 5, acted: true);
      now = now.add(const Duration(days: 1));
    }
    expect(seen, {'a', 'b', 'c'});
    expect(pick(state, now).$1, isNull);

    var on = true;
    final only = [tip('x', when: (_) => on)];
    final up = pick(NexTipState(firstSeenAt: day1), day2, tips: only);
    expect(up.$1?.id, 'x');
    on = false;
    final gone = pick(up.$2, day2.add(const Duration(minutes: 5)), tips: only);
    expect(gone.$1, isNull);
    expect(gone.$2.current, isNull);

    final again = NexTipState.parse(up.$2.toJson());
    expect(again.current, 'x');
    expect(again.shown.keys, ['x']);
    expect(NexTipState.parse('not json').shown, isEmpty);
  });

  test(
    'every tip in the catalogue has its words, and ids are unique',
    () async {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = await AppLocalizations.delegate.load(locale);
        for (final t in nexTips) {
          expect(t.title(l10n).trim(), isNotEmpty, reason: t.id);
          expect(t.body(l10n).trim(), isNotEmpty, reason: t.id);
          if (t.target != null) expect(t.action, isNotNull, reason: t.id);
        }
      }
      expect(nexTips.map((t) => t.id).toSet(), hasLength(nexTips.length));
    },
  );

  for (final locale in ['en', 'fa']) {
    testWidgets('the card closes, and its button leads somewhere ($locale)', (
      tester,
    ) async {
      final opened = <NexTipTarget>[];
      final start = NexTipState(firstSeenAt: day1);
      await h.preferences.setTipState(start.toJson());
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NexHomeTip(
              preferences: h.preferences,
              notes: notes(5),
              onOpen: opened.add,
              clock: () => day2,
              tips: [
                NexTip(
                  id: 'go',
                  icon: Icons.widgets_outlined,
                  hue: NexHue.violet,
                  title: (_) => 'Go somewhere',
                  body: (_) => 'Somewhere useful.',
                  target: NexTipTarget.tools,
                  action: (l) => l.tipOpenTools,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Go somewhere'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-tip-action')));
      await tester.pumpAndSettle();
      expect(opened, [NexTipTarget.tools]);
      expect(find.text('Go somewhere'), findsNothing);
      final saved = NexTipState.parse(h.preferences.tipState);
      expect(saved.current, isNull);
      expect(saved.shown.keys, ['go']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('turned off in Home layout, no tip', (tester) async {
    await h.preferences.setTipState(NexTipState(firstSeenAt: day1).toJson());
    await h.preferences.setShowTips(false);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NexHomeTip(
            preferences: h.preferences,
            notes: notes(5),
            onOpen: (_) {},
            clock: () => day2,
            tips: [tip('a')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Title a'), findsNothing);
    await h.preferences.setShowTips(true);
    await tester.pumpAndSettle();
    expect(find.text('Title a'), findsOneWidget);
  });
}
