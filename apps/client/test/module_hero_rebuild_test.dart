import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_hero.dart';
import 'package:nex_ui/nex_ui.dart';

/// NEX-UI-08: the hero's entrance used to rebuild the whole hero card — the
/// wash, the border, the big rotating icon, the headline, every chip — on
/// every frame of its ~300 ms arrival, on all thirteen module screens. The
/// card subtree is the tween's cached `child` now; only the fade and the
/// rise, and the icon's own lockstep rotation, animate.
void main() {
  Widget host() => MaterialApp(
    theme: nexLightTheme(),
    home: const Scaffold(
      body: Center(
        child: SizedBox(
          width: 340,
          child: NexModuleHero(
            moduleId: 'habits',
            icon: Icons.check_circle_outline_rounded,
            headline: '12 days free',
            eyebrow: 'Smoke free',
            caption: 'Keep going',
            chips: ['2 saved', '1 due'],
          ),
        ),
      ),
    ),
  );

  testWidgets('the hero arrives without rebuilding its card every frame', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    // The first frame builds the card once, entrances begin.
    await tester.pump();

    // The card's wash is the heavy subtree (DecoratedBox → ClipRRect →
    // Stack → …). Whether it was rebuilt is observable as a *widget
    // identity*: the cached `child` hands the framework the very same
    // widget across every tick of the entrance, where the per-tick
    // `cardAt(t)` used to construct a fresh subtree each frame.
    DecoratedBox wash() => tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(NexModuleHero),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    Transform rotation() => tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(NexModuleHero),
            matching: find.byType(Transform),
          )
          .first,
    );

    var spinChanges = 0;
    var rebuilt = 0;
    for (var i = 0; i < 12; i++) {
      final washAt = wash();
      final angleBefore = rotation().transform;
      await tester.pump(const Duration(milliseconds: 32));
      if (!identical(washAt, wash())) rebuilt++;
      if (rotation().transform != angleBefore) spinChanges++;
    }

    expect(
      rebuilt,
      0,
      reason:
          'the hero card was the tween\'s cached child, not a fresh '
          'subtree per tick',
    );
    expect(
      spinChanges,
      greaterThan(0),
      reason: 'the big icon still turns into place',
    );

    await tester.pumpAndSettle();
    expect(find.text('12 days free'), findsOneWidget);
    expect(find.text('2 saved'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsNWidgets(2));
  });
}
