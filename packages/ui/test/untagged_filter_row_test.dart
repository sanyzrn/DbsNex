import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  for (final rtl in [false, true]) {
    testWidgets('$rtl virtual Untagged stays after newly appended real tags', (
      tester,
    ) async {
      final tags = [Tag(id: 'a', name: 'Work', createdAt: DateTime(2026))];
      var untags = 0, clears = 0;
      Future<void> pump() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: TagFilterRow(
                tags: tags,
                selectedTagIds: const {},
                onSelected: (_) {},
                untaggedLabel: 'Untagged',
                untaggedSelected: true,
                onUntagged: () {
                  untags++;
                },
                onClearAll: () {
                  clears++;
                },
              ),
            ),
          ),
        ),
      );
      await pump();
      await tester.tap(find.text('Untagged'));
      expect(untags, 1);
      tags.add(Tag(id: 'b', name: 'New tag', createdAt: DateTime(2026)));
      await pump();
      final untagged = tester.getCenter(find.text('Untagged')).dx;
      final added = tester.getCenter(find.text('New tag')).dx;
      expect(rtl ? untagged < added : untagged > added, isTrue);
      await tester.tap(find.text('All'));
      expect(clears, 1);
      expect(tags.map((tag) => tag.id), ['a', 'b']);
    });
  }
}
