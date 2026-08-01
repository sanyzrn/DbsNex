import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/tag_picker.dart';

Tag _tag(String id, String name) =>
    Tag(id: id, name: name, createdAt: DateTime.utc(2026));

Widget _harness(
  ValueChanged<Future<TagChoice?>> onOpened, {
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

void main() {
  testWidgets('tags lay out in a wrap, not one per row', (tester) async {
    await tester.pumpWidget(
      _harness(
        (_) {},
        tags: [_tag('1', 'Idea'), _tag('2', 'Work'), _tag('3', 'Errands')],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(Wrap), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    for (final name in ['Idea', 'Work', 'Errands']) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('tapping a tag returns it as the choice', (tester) async {
    late Future<TagChoice?> pending;
    await tester.pumpWidget(
      _harness((future) => pending = future, tags: [_tag('1', 'Idea')]),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Idea'));
    await tester.pumpAndSettle();

    final choice = await pending;
    expect(choice?.tag?.id, '1');
  });

  testWidgets(
    'a tag already on the note shows a check and does not pop again',
    (tester) async {
      await tester.pumpWidget(
        _harness((_) {}, tags: [_tag('1', 'Idea')], alreadyOn: {'1'}),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('Idea'));
      await tester.pumpAndSettle();

      // Disabled for a tag already applied — the sheet is still up, nothing
      // popped it.
      expect(find.text('Idea'), findsOneWidget, reason: 'sheet stayed open');
    },
  );
}
