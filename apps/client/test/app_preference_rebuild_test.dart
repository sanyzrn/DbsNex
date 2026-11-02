import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';
import 'support/nex_harness.dart';

void main() {
  testWidgets(
    'feature writes preserve both themes; appearance and locale still update',
    (tester) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      await h.preferences.setHaptics(false);
      await h.preferences.setAiUserName('Saeed');
      await h.preferences.setDisplayName('Saeed');
      await tester.pump();
      final after = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(identical(after.theme, app.theme), isTrue);
      expect(identical(after.darkTheme, app.darkTheme), isTrue);
      expect(nexHapticsEnabled, isFalse);
      await tester.pumpAndSettle();
      expect(find.textContaining('Saeed'), findsOneWidget);
      await h.preferences.setThemePreset('still');
      await tester.pumpAndSettle();
      final themed = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(identical(themed.theme, app.theme), isFalse);
      await h.preferences.setLocale('fa');
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('fa'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
