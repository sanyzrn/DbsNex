import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/occasions/module.dart';

import '../../support/nex_harness.dart';

/// Records the reminders it is asked for, instead of asking the phone.
class _Store extends NexModuleStore {
  _Store(super.services, super.module);

  final set = <String, ({DateTime at, String title, String body})>{};
  final cleared = <String>{};

  @override
  Future<bool> setReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    set[key] = (at: at, title: title, body: body);
    return true;
  }

  @override
  Future<void> clearReminder(String key) async => cleared.add(key);
}

/// 2.4.0: a date keeps ringing without its screen being opened — the module
/// renews its alarms as Nex starts and returns.
void main() {
  late NexTestHarness h;
  setUp(() async => h = await NexTestHarness.create());
  tearDown(() => h.dispose());

  test('keepUp arms a day before and on the day for each date', () async {
    final store = _Store(h.services, 'occasions');
    final soon = DateTime.now().add(const Duration(days: 10));
    await store.put('occasion', 'a', {
      'v': 1,
      'title': "Sara's birthday",
      'kind': 'birthday',
      'calendar': 'gregorian',
      'month': soon.month,
      'day': soon.day,
      'yearKnown': false,
      'remindDays': 1,
      'remindMinutes': 9 * 60,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await store.put('occasion', 'b', {
      'v': 1,
      'title': 'No reminder',
      'kind': 'other',
      'calendar': 'gregorian',
      'month': soon.month,
      'day': soon.day,
      'yearKnown': false,
      'createdAt': DateTime.now().toIso8601String(),
    });
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await const OccasionsModule().keepUp(store, l10n);

    expect(store.set.keys, containsAll(['occ:a:a', 'occ:a:c']));
    expect(store.set.keys.where((k) => k.startsWith('occ:b')), isEmpty);
    expect(store.set['occ:a:c']!.at.day, soon.day);
    expect(store.set['occ:a:c']!.title, contains("Sara's birthday"));
  });
}
