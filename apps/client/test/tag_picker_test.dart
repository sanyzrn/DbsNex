import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/tag_picker.dart';

Tag _tag(String id, String name) =>
    Tag(id: id, name: name, createdAt: DateTime.utc(2026));

Widget _harness(
  ValueChanged<Future<List<TagChoice>?>> onOpened, {
  required List<Tag> tags,
  Set<String> alreadyOn = const {},
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => onOpened(
          TagPickerSheet.show(context, tags: tags, alreadyOn: alreadyOn),
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, Widget harness) async {
  await tester.pumpWidget(harness);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _add(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tags lay out in a wrap, not one per row', (tester) async {
    await _open(
      tester,
      _harness(
        (_) {},
        tags: [_tag('1', 'Idea'), _tag('2', 'Work'), _tag('3', 'Errands')],
      ),
    );

    expect(find.byType(Wrap), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    for (final name in ['Idea', 'Work', 'Errands']) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('a tap ticks in place; Add commits the choice', (tester) async {
    late Future<List<TagChoice>?> pending;
    await _open(
      tester,
      _harness((future) => pending = future, tags: [_tag('1', 'Idea')]),
    );

    // The pick itself no longer closes the sheet — the whole visit commits
    // with one Add.
    await tester.tap(find.text('Idea'));
    await tester.pumpAndSettle();
    expect(find.byType(TagPickerSheet), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await _add(tester);
    final choices = await pending;
    expect(choices, hasLength(1));
    expect(choices.single.tag?.id, '1');
  });

  testWidgets('several tags tick in one visit and commit together', (
    tester,
  ) async {
    late Future<List<TagChoice>?> pending;
    await _open(
      tester,
      _harness(
        (future) => pending = future,
        tags: [_tag('1', 'Idea'), _tag('2', 'Work')],
      ),
    );

    await tester.tap(find.text('Idea'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsNWidgets(2));

    await _add(tester);
    final choices = await pending;
    expect(choices?.map((c) => c.tag?.id).toSet(), {'1', '2'});
  });

  testWidgets('a typed name becomes a ticked pill that Add creates', (
    tester,
  ) async {
    late Future<List<TagChoice>?> pending;
    await _open(
      tester,
      _harness((future) => pending = future, tags: [_tag('1', 'Idea')]),
    );

    await tester.enterText(find.byType(TextField), 'Fresh');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fresh').last);
    await tester.pumpAndSettle();

    // Off the create row and onto a pill of its own: everything Add will do
    // is on screen, and the search field is clear for another name.
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    await _add(tester);
    final choices = await pending;
    expect(choices, hasLength(1));
    expect(choices.single.name, 'Fresh');
    expect(choices.single.tag, isNull);
  });

  testWidgets('the fourth tag cannot be chosen or created', (tester) async {
    await _open(
      tester,
      _harness(
        (_) {},
        tags: [
          _tag('1', 'Idea'),
          _tag('2', 'Work'),
          _tag('3', 'Errands'),
          _tag('4', 'Other'),
        ],
        alreadyOn: {'1', '2', '3'},
      ),
    );

    expect(find.textContaining('at most 3 tags'), findsOneWidget);
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    // Not ticked, and the sheet's Add has nothing to commit.
    expect(find.byIcon(Icons.check), findsNWidgets(3));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.byType(TagPickerSheet), findsOneWidget);
  });

  testWidgets(
    'ticking the third tag fills the note; the tick stays reversible',
    (tester) async {
      await _open(
        tester,
        _harness(
          (_) {},
          tags: [
            _tag('1', 'Idea'),
            _tag('2', 'Work'),
            _tag('3', 'Errands'),
            _tag('4', 'Other'),
          ],
          alreadyOn: {'1'},
        ),
      );

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Errands'));
      await tester.pumpAndSettle();

      // The note is now full — with 1 already on and 2 ticked — so a third
      // tick is refused, but an earlier one can still come off.
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsNWidgets(3)); // 1 + 2 ticked

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsNWidgets(2));
    },
  );

  testWidgets(
    'a tag already on the note shows a check and does not pop again',
    (tester) async {
      await _open(
        tester,
        _harness((_) {}, tags: [_tag('1', 'Idea')], alreadyOn: {'1'}),
      );

      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('Idea'));
      await tester.pumpAndSettle();

      // Disabled for a tag already applied — the sheet is still up, nothing
      // popped it.
      expect(find.text('Idea'), findsOneWidget, reason: 'sheet stayed open');
    },
  );
}
