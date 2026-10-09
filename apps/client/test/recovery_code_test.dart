import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/recovery_code.dart';

/// A recovery code copies with one tap.
void main() {
  testWidgets('a tap copies the code and says so', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: NexRecoveryCode('abc-123')),
      ),
    );
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    await tester.tap(find.text('abc-123'));
    await tester.pump();
    expect(copied, ['abc-123']);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    // The private clipboard clears itself after half a minute.
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('TalkBack hears the code and can copy it (LOC-01)', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: NexRecoveryCode('AB12-CD34')),
      ),
    );
    final node = tester.getSemantics(find.byType(NexRecoveryCode));
    expect(node.label, contains('AB12-CD34'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(find.semantics.byLabel(RegExp('AB12-CD34')));
    await tester.pump();
    expect(copied, ['AB12-CD34']);
    await tester.pump(const Duration(seconds: 33));
    semantics.dispose();
  });
}
