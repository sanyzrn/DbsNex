import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  for (final rtl in [false, true]) {
    for (final dark in [false, true]) {
      for (final density in NexCardDensity.values) {
        testWidgets(
          '$rtl $dark $density urgency and caption preserve primary content',
          (tester) async {
            final now = DateTime.now();
            final body = rtl ? 'متن اصلی یادداشت' : 'Primary note text';
            final caption = rtl
                ? 'توضیح ثانویه یادداشت'
                : 'Secondary note caption';
            final note = Note(
              id: 'n',
              type: NoteType.text,
              content: body,
              caption: caption,
              isUrgent: true,
              pinnedAt: now,
              dueAt: now.add(const Duration(hours: 1)),
              attachmentCount: 2,
              createdAt: now,
              updatedAt: now,
              deviceId: 'test',
              rev: 1,
              syncState: SyncState.pending,
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? nexDarkTheme() : nexLightTheme(),
                home: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.8),
                  ),
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Scaffold(
                      body: NexCardDensityScope(
                        density: density,
                        child: SizedBox(
                          width: 320,
                          child: NoteCard(note: note),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text(body), findsOneWidget);
            expect(find.text(caption), findsOneWidget);
            final flame = find.byKey(const ValueKey('note-urgent-mark'));
            expect(flame, findsOneWidget);
            final marks = find.byKey(const ValueKey('note-status-marks'));
            expect(marks, findsOneWidget);
            expect(find.descendant(of: marks, matching: flame), findsOneWidget);
            expect(
              find.descendant(
                of: marks,
                matching: find.byIcon(Icons.attach_file),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: marks,
                matching: find.byIcon(Icons.notifications_active_outlined),
              ),
              findsOneWidget,
            );
            expect(
              tester.getRect(find.text(caption)).top,
              greaterThanOrEqualTo(tester.getRect(find.text(body)).bottom),
            );
            expect(note.displayText, body);
            expect(note.isUrgent, isTrue);
            expect(note.pinnedAt, isNotNull);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
