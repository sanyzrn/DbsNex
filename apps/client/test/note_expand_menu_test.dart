import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/hold_menu.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_expand_', onboarded: true);
    await harness.preferences.setHoldMenuActions([NexHoldAction.expand]);
  });
  tearDown(() => harness.dispose());

  for (final long in [false, true]) {
    testWidgets(
      'Show in full only when extra content is visible (long=$long)',
      (tester) async {
        final captured = await harness.services.captureText(
          long ? List.filled(100, 'words to read').join(' ') : 'short note',
        );
        final note = captured!;
        await tester.pumpWidget(
          NexApp(services: harness.services, preferences: harness.preferences),
        );
        await tester.pumpAndSettle();
        final card = find.byWidgetPredicate(
          (widget) => widget is NoteCard && widget.note.id == note.id,
        );
        final l10n = AppLocalizations.of(tester.element(card));
        await tester.longPress(card);
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.expandCard),
          long ? findsOneWidget : findsNothing,
        );
        if (long) {
          await tester.tap(find.text(l10n.expandCard));
          await tester.pumpAndSettle();
          expect(harness.preferences.isNoteExpanded(note.id), isTrue);
          await tester.longPress(card);
          await tester.pumpAndSettle();
          expect(find.text(l10n.collapseCard), findsOneWidget);
        }
      },
    );
  }
}
