import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/nex_module_store.dart';
import 'package:nex_client/modules/occasions/occasion_reminders.dart';
import 'package:nex_client/modules/words/module.dart';
import 'package:nex_client/modules/habits/habit_reminder.dart';
import 'package:nex_client/platform/module_keep_up.dart';
import 'support/nex_harness.dart';

class _TrackingStore extends NexModuleStore {
  _TrackingStore(super.services, super.module);
  final withdrawn = <String>[];
  final cleared = <String>[];
  @override
  Future<void> withdrawReminder(String key) async => withdrawn.add(key);
  @override
  Future<void> clearReminder(String key) async => cleared.add(key);
  @override
  Future<bool> setReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) async => true;
}

void main() {
  late NexTestHarness h;
  setUp(() async => h = await NexTestHarness.create());
  tearDown(() => h.dispose());
  final l10n = lookupAppLocalizations(const Locale('en'));
  test(
    'automatic occasion cleanup withdraws slots; explicit changes cancel them',
    () async {
      final store = _TrackingStore(h.services, 'occasions');
      await store.put('occasion', 'one', {
        'title': 'Birthday',
        'kind': 'birthday',
        'calendar': 'gregorian',
        'month': 12,
        'day': 25,
        'remindDays': 0,
      });
      await renewOccasionReminders(store, l10n);
      expect(store.withdrawn, containsAll(['occ:one:a', 'occ:one:b']));
      expect(store.cleared, isEmpty);
      await clearOccasionReminders(store, 'one');
      expect(store.cleared, isNotEmpty);
    },
  );
  test(
    'automatic habit and word upkeep cannot dismiss existing notices',
    () async {
      final habits = _TrackingStore(h.services, 'habits');
      await habits.put('habit', 'one', {
        'name': 'Walking',
        'schedule': 'daily',
        'createdAt': DateTime.now().toIso8601String(),
      });
      await habitsKeepUp(habits, l10n);
      expect(habits.cleared, isEmpty);
      expect(habits.withdrawn, isNotEmpty);
      final words = _TrackingStore(h.services, 'words');
      await const WordsModule().keepUp(words, l10n);
      expect(words.cleared, isEmpty);
      expect(words.withdrawn, isNotEmpty);
    },
  );
  test(
    'overlapping launch and resume maintenance shares one ordered flight',
    () async {
      final first = nexRefreshReminders(h.services, h.preferences);
      final second = nexRefreshReminders(h.services, h.preferences);
      expect(identical(first, second), isTrue);
      await first;
    },
  );
}
