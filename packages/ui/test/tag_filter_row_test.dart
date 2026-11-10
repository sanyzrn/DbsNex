import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// What the row of pills promises now that more than one can be on.
///
/// The old row held a single id, so picking a second tag silently dropped the
/// first and the row could not answer "these two". Toggling lives inside the
/// widget rather than at each call site, so that everyone gets the same
/// answer to the one question with two plausible answers: what happens when
/// the last selected tag is turned off.
void main() {
  Tag tag(String id, String name) =>
      Tag(id: id, name: name, createdAt: DateTime.utc(2026));

  final tags = [tag('a', 'Work'), tag('b', 'Home'), tag('c', 'Idea')];

  for (final dark in [false, true]) {
    for (final comfort in [false, true]) {
      for (final seed in [null, const Color(0xFFFFD24A)]) {
        testWidgets('selected filter is readable: dark=$dark comfort=$comfort '
            'custom=${seed != null}', (tester) async {
          final theme = dark
              ? nexDarkTheme(comfortMode: comfort, accentSeed: seed)
              : nexLightTheme(comfortMode: comfort, accentSeed: seed);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Directionality(
                textDirection: comfort ? TextDirection.rtl : TextDirection.ltr,
                child: Scaffold(
                  body: TagFilterRow(
                    tags: tags,
                    selectedTagIds: const {'a'},
                    onSelected: (_) {},
                  ),
                ),
              ),
            ),
          );
          final label = find.text('Work');
          final pill = find.ancestor(
            of: label,
            matching: find.byType(NexTappable),
          );
          final material = tester.widget<Material>(
            find.descendant(of: pill, matching: find.byType(Material)),
          );
          final foreground = tester.widget<Text>(label).style!.color!;
          final background = Color.alphaBlend(
            material.color!,
            theme.scaffoldBackgroundColor,
          );
          expect(
            nexContrast(foreground, background),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            material.color,
            theme.colorScheme.primary.withValues(alpha: .12),
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  /// Pumps the row and hands back the last selection it reported.
  Future<Set<String>? Function()> pump(
    WidgetTester tester,
    Set<String> selected,
  ) async {
    Set<String>? latest;
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        home: Scaffold(
          body: TagFilterRow(
            tags: tags,
            selectedTagIds: selected,
            allLabel: 'All',
            onSelected: (value) => latest = value,
          ),
        ),
      ),
    );
    return () => latest;
  }

  testWidgets('counts remain tiny, muted, and independent of selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        home: Scaffold(
          body: TagFilterRow(
            tags: tags.take(2).toList(),
            tagCounts: const {'a': 4, 'b': 3},
            selectedTagIds: const {'a'},
            onSelected: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(tester.widget<Text>(find.text('4')).style?.fontSize, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second tag joins the first rather than replacing it', (
    tester,
  ) async {
    final reported = await pump(tester, {'a'});
    await tester.tap(find.text('Home'));
    expect(reported(), {'a', 'b'});
  });

  testWidgets('tapping a selected tag turns it off', (tester) async {
    final reported = await pump(tester, {'a', 'b'});
    await tester.tap(find.text('Work'));
    expect(reported(), {'b'});
  });

  testWidgets('turning the last one off is the same as All', (tester) async {
    final reported = await pump(tester, {'a'});
    await tester.tap(find.text('Work'));
    expect(
      reported(),
      isEmpty,
      reason: 'an empty set is what "no filter" is spelled as',
    );
  });

  testWidgets('All clears the lot, and cannot put one back', (tester) async {
    final reported = await pump(tester, {'a', 'c'});
    await tester.tap(find.text('All'));
    expect(reported(), isEmpty);

    // Already clear: tapping the absence of a filter cannot create one.
    final again = await pump(tester, const {});
    await tester.tap(find.text('All'));
    expect(again(), isEmpty);
  });

  testWidgets('every selected pill is drawn as selected, not just one', (
    tester,
  ) async {
    await pump(tester, {'a', 'c'});
    // `NexTappable.selected` is what the pill paints from, and it is the only
    // thing that says "you are looking through this one".
    Set<String> lit() => {
      for (final t in tags)
        if (tester
            .widget<NexTappable>(
              find.ancestor(
                of: find.text(t.name),
                matching: find.byType(NexTappable),
              ),
            )
            .selected)
          t.id,
    };
    expect(lit(), {'a', 'c'});
  });

  testWidgets('the caller is never handed the set it gave', (tester) async {
    // Mutating the incoming set in place would change the caller's state
    // without a rebuild, and `const {}` would throw outright.
    const given = <String>{'a'};
    final reported = await pump(tester, given);
    await tester.tap(find.text('Home'));
    expect(given, {'a'});
    expect(reported(), isNot(same(given)));
  });

  testWidgets('a Latin tag reads left-to-right under a Persian row', (
    tester,
  ) async {
    // `C++` worn by an RTL row of pills used to render as `++C` — the
    // glyphs followed the row's direction instead of the name's own. The
    // count beside a label already took its own direction; the label now
    // does too.
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: TagFilterRow(
              tags: [tag('c', 'C++')],
              selectedTagIds: {},
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    final label = tester.widget<Text>(find.text('C++'));
    expect(label.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });
  for (final look in ['light', 'dark', 'glass']) {
    for (final rtl in [false, true]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets(
          'filter matches tag surface ($look, rtl=$rtl, scale=$scale)',
          (tester) async {
            var opened = false;
            await tester.pumpWidget(
              MaterialApp(
                theme: look == 'dark'
                    ? nexDarkTheme()
                    : nexLightTheme(liquidGlass: look == 'glass'),
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Scaffold(
                      body: TagFilterRow(
                        tags: [tag('work', rtl ? 'کار' : 'Work')],
                        selectedTagIds: const {},
                        leading: NexTagFilterButton(
                          label: 'Filters',
                          onTap: () => opened = true,
                        ),
                        onSelected: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            );
            final filter = find.descendant(
              of: find.byType(NexTagFilterButton),
              matching: find.byType(NexGlassSurface),
            );
            final pill = find.ancestor(
              of: find.text(rtl ? 'کار' : 'Work'),
              matching: find.byType(NexGlassSurface),
            );
            expect(
              tester.getSize(filter).height,
              closeTo(tester.getSize(pill).height, 0.6),
            );
            final target = find.descendant(
              of: find.byType(NexTagFilterButton),
              matching: find.byType(NexTappable),
            );
            expect(
              tester.getSize(target).height,
              greaterThanOrEqualTo(nexMinTapTarget),
            );
            await tester.tap(find.byType(NexTagFilterButton));
            expect(opened, isTrue);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
