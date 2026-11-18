import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/platform/nex_preferences.dart';

/// NEX-UI-01: text typed into a settings field persists per keystroke, but
/// notifies when the typing pauses. The timeline rebuilds wholesale on
/// every preferences notify — a sentence typed into a covered settings
/// screen used to buy one whole covered-screen rebuild per character.
void main() {
  testWidgets('typing notifies once, on pause — and is saved all along', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await NexPreferences.load();
    addTearDown(prefs.dispose);

    var notified = 0;
    prefs.addListener(() => notified++);

    await prefs.setAiInstruction('one');
    await prefs.setAiInstruction('one two');
    await prefs.setAiInstruction('one two three');
    await prefs.setAiInstruction('one two three four');

    expect(notified, 0, reason: 'typing itself never notified');
    expect(
      prefs.aiInstruction,
      'one two three four',
      reason: 'each keystroke is on disk the moment it happens',
    );

    await tester.pump(const Duration(milliseconds: 400));
    expect(notified, 1, reason: 'one notify when the typing paused');
    expect(prefs.aiInstruction, 'one two three four');

    await prefs.setAiUserName('a name');
    await prefs.setBriefInstruction('an instruction');
    expect(notified, 1, reason: 'more typing still holds the notify');
    await tester.pump(const Duration(milliseconds: 400));
    expect(notified, 2);
    expect(prefs.aiUserName, 'a name');
    expect(prefs.briefInstruction, 'an instruction');
  });

  testWidgets('any other change flushes a held typing notify', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await NexPreferences.load();
    addTearDown(prefs.dispose);

    var notified = 0;
    prefs.addListener(() => notified++);

    await prefs.setAiInstruction('half-typed');
    expect(notified, 0);
    await prefs.setHaptics(false);

    // The toggle's notify carried the pending text with it — a listener
    // reading through getters sees both — and nothing else follows.
    expect(notified, 1);
    expect(prefs.aiInstruction, 'half-typed');
    expect(prefs.haptics, isFalse);

    await tester.pump(const Duration(milliseconds: 400));
    expect(notified, 1, reason: 'no second notify behind the flush');
  });

  testWidgets('a pending typing notify dies with the preferences', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await NexPreferences.load();

    var notified = 0;
    prefs.addListener(() => notified++);

    await prefs.setAiInstruction('never settled');
    prefs.dispose();

    await tester.pump(const Duration(milliseconds: 500));
    expect(notified, 0, reason: 'disposed mid-pause notifies nobody');
    expect(tester.takeException(), isNull);
  });
}
