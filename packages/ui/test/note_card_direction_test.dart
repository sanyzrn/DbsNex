import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

Note textNote(String content) {
  final now = DateTime.utc(2026, 7, 28);
  return Note(
    id: 'n1',
    type: NoteType.text,
    content: content,
    createdAt: now,
    updatedAt: now,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );
}

Widget host(Note note) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, child: NoteCard(note: note)),
      ),
    );

void main() {
  const persian = 'نمونه متن فارسی راست چین شده';
  const english = 'sample sample';

  testWidgets('a right-to-left note turns its text, not its card',
      (tester) async {
    await tester.pumpWidget(host(textNote(persian)));

    // The paragraph itself is right-to-left and flush right.
    final body = tester.widget<Text>(find.text(persian));
    expect(body.textDirection, TextDirection.rtl);
    expect(body.textAlign, TextAlign.right);

    // ...and nothing else moved. The type icon and the date stay on the left,
    // exactly where they sit on an English card: wrapping the whole card in a
    // Directionality mirrored the icon, the date and the tags too.
    final card = tester.getRect(find.byType(NoteCard));
    final icon = tester.getCenter(find.byIcon(Icons.short_text));
    final date = tester.getCenter(find.text('Jul 28'));
    expect(icon.dx, lessThan(card.center.dx), reason: 'icon stays leading');
    expect(date.dx, lessThan(card.center.dx), reason: 'date stays leading');
  });

  testWidgets('a left-to-right note is laid out identically', (tester) async {
    await tester.pumpWidget(host(textNote(english)));
    final body = tester.widget<Text>(find.text(english));
    expect(body.textDirection, TextDirection.ltr);
    expect(body.textAlign, TextAlign.start);

    final card = tester.getRect(find.byType(NoteCard));
    expect(tester.getCenter(find.byIcon(Icons.short_text)).dx,
        lessThan(card.center.dx));
    expect(tester.getCenter(find.text('Jul 28')).dx, lessThan(card.center.dx));
  });

  testWidgets('the icon sits in the same place either way', (tester) async {
    await tester.pumpWidget(host(textNote(english)));
    final ltrIcon = tester.getCenter(find.byIcon(Icons.short_text));

    await tester.pumpWidget(host(textNote(persian)));
    final rtlIcon = tester.getCenter(find.byIcon(Icons.short_text));

    expect(rtlIcon.dx, closeTo(ltrIcon.dx, 0.5));
  });
}
