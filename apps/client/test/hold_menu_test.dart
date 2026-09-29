import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/hold_menu.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The hold menu's contents are the user's to choose.
void main() {
  test('by default: pin, copy, edit, remind and delete', () async {
    // Open and Add tag left the default: the card opens with a tap and tags
    // with a swipe, so both were a longer way to something already one
    // gesture away.
    SharedPreferences.setMockInitialValues({});
    final preferences = await NexPreferences.load();
    expect(preferences.holdMenuActions, [
      NexHoldAction.pin,
      NexHoldAction.copy,
      NexHoldAction.edit,
      NexHoldAction.remind,
      NexHoldAction.delete,
    ]);
  });

  test('a choice is kept in menu order, Delete last', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await NexPreferences.load();
    await preferences.setHoldMenuActions([
      NexHoldAction.delete,
      NexHoldAction.translate,
      NexHoldAction.share,
    ]);
    final reloaded = await NexPreferences.load();
    expect(reloaded.holdMenuActions, [
      NexHoldAction.share,
      NexHoldAction.translate,
      NexHoldAction.delete,
    ]);
  });

  test('a name this build does not know is skipped', () async {
    SharedPreferences.setMockInitialValues({
      'hold_menu.actions': ['copy', 'teleport'],
    });
    final preferences = await NexPreferences.load();
    expect(preferences.holdMenuActions, [NexHoldAction.copy]);
  });
}
