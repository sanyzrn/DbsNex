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
}
