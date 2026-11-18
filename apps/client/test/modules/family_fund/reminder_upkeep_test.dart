import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations_fa.dart';
import 'package:nex_client/modules/family_fund/reminder_upkeep.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';
import 'model_test.dart' show example;

class _AlarmStore extends NexModuleStore {
  _AlarmStore(NexTestHarness h) : super(h.services, 'family_fund');
  final held = <String, Map<String, Object?>>{};
  final armed = <String, DateTime>{};
  final bodies = <String, String>{};

  @override
  Future<List<ModuleRecord>> list(String kind) async => kind == '__reminder'
      ? [
          for (final MapEntry(:key, :value) in held.entries)
            ModuleRecord(
              module: 'family_fund',
              kind: '__reminder',
              id: key,
              body: value,
              updatedAt: DateTime(2026),
            ),
        ]
      : await super.list(kind);

  @override
  Future<bool> setReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    armed[key] = at;
    bodies[key] = body;
    return true;
  }
}

/// A Jalali day at [hour].
DateTime _j(int y, int m, int d, [int hour = 0]) {
  final g = nexGregorianDate(y, m, d);
  return DateTime(g.year, g.month, g.day, hour);
}

/// 2.8.4 review: a fund's contribution and draw days come every month, so
/// an alert whose day has passed moves to the next one.
void main() {
  late NexTestHarness h;
  late _AlarmStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'fund_upkeep_');
    store = _AlarmStore(h);
  });
  tearDown(() => h.dispose());

  test('the next ring is the same clock time on the next fund day', () {
    // 10 Aban 1405 (1 Nov 2026); contribution day 5 → 5 Azar, at 09:30.
    final now = _j(1405, 8, 10, 12);
    final next = FundReminderUpkeep.nextRing(now, 5, 9, 30);
    final p = nexPersianDate(next);
    expect((p.month, p.day, next.hour, next.minute), (9, 5, 9, 30));
    // The day 31 of a 30-day month is its last day.
    final esfand = FundReminderUpkeep.nextRing(
      nexGregorianDate(1405, 12, 1),
      31,
      9,
      0,
    );
    expect(nexPersianDate(esfand).month, 12);
  });

  test('a passed alert rolls on; a cleared one, today’s, and one for '
      'a fund that is gone stay', () async {
    final fund = example(const NexModuleMonth(true, 1405, 7));
    await store.put('fund', 'x', fund.body);
    final now = _j(1405, 8, 10, 12);
    String at(DateTime d) => d.toUtc().toIso8601String();
    store.held['fund-contribution:x'] = {'at': at(_j(1405, 7, 30, 9))};
    store.held['fund-draw:x'] = {
      'at': at(now.subtract(const Duration(hours: 2))),
    };
    store.held['fund-draw:gone'] = {'at': at(_j(1405, 7, 1, 9))};
    await FundReminderUpkeep.roll(store, AppLocalizationsFa(), now: now);
    expect(store.armed.keys, ['fund-contribution:x']);
    final next = store.armed['fund-contribution:x']!;
    // Payment day 31 → the last day of Aban, 30 Aban, at 09:00.
    expect(nexPersianDate(next).day, 30);
    expect(next.hour, 9);
    expect(store.bodies['fund-contribution:x'], contains('Family'));
  });
}
