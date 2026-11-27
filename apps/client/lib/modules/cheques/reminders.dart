import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'dues.dart';
import 'plan_model.dart';
import 'strings.dart';
import 'money_format.dart' show formatNumber;

List<({int days, DateTime at})> chequeAlarmPlan(Cheque c, DateTime now) {
  final day = c.actionDay;
  if (day == null || c.raw['remind'] != true) return [];
  final dues = ChequeDues([c]).duesBetween(day, day);
  if (dues.isEmpty || dues.single.done) return [];
  final date = dues.single.at, minutes = c.raw['minutes'] as int;
  return [
      for (final d in c.raw['reminderDays'] as List)
        (
          days: d as int,
          at: DateTime(
            date.year,
            date.month,
            date.day - d,
            minutes ~/ 60,
            minutes % 60,
          ),
        ),
    ].where((a) => a.at.isAfter(now)).toList()
    ..sort((a, b) => a.at.compareTo(b.at));
}

String chequeAlarmKey(String id, int days) => 'cheque:$id:$days';
Future<bool> armCheque(
  NexModuleStore store,
  Cheque c,
  AppLocalizations l10n, {
  DateTime? now,
  bool upkeep = false,
  List<ModuleRecord>? existing,
}) async {
  final plan = chequeAlarmPlan(c, now ?? DateTime.now());
  final alarms = existing ?? await store.list('__reminder');
  final prefix = 'cheque:${c.id}:';
  final scheduled = {for (final alarm in plan) alarm.days: alarm.at};
  final keys = {
    for (final d in [
      if (!upkeep) ...[0, 1, 3, 7, 14, 30],
      ...scheduled.keys,
    ])
      chequeAlarmKey(c.id, d),
    for (final alarm in alarms)
      if (alarm.id.startsWith(prefix) &&
          int.tryParse(alarm.id.substring(prefix.length)) != null)
        alarm.id,
  };
  var ok = true;
  for (final key in keys) {
    final days = int.parse(key.substring(prefix.length));
    final at = scheduled[days];
    if (at == null) {
      if (upkeep) {
        await store.withdrawReminder(key);
      } else {
        await store.clearReminder(key);
      }
    } else {
      ok =
          await store.setReminder(
            key,
            sourceKind: 'cheque',
            sourceId: c.id,
            at: at,
            title: chequeStrings.text(l10n, 'title'),
            body: chequeAlarmText(c, l10n, days: days),
          ) &&
          ok;
    }
  }
  return ok;
}

Future<void> renewCheques(NexModuleStore store, AppLocalizations l10n) async {
  await renewPlans(store, l10n);
  final alarms = await store.list('__reminder');
  for (final row in await store.list('cheque')) {
    await armCheque(
      store,
      Cheque(row.id, row.body),
      l10n,
      upkeep: true,
      existing: alarms,
    );
  }
}

Future<bool> renewPlans(
  NexModuleStore store,
  AppLocalizations l10n, {
  String? planId,
  DateTime? now,
}) async {
  final plans = planId == null
      ? [
          for (final row in await store.list('plan'))
            InstalmentPlan(row.id, row.body),
        ]
      : [
          if (await store.get('plan', planId)
              case final Map<String, Object?> body)
            InstalmentPlan(planId, body),
        ];
  final existing = await store.list('__reminder');
  final clock = now ?? DateTime.now();
  var ok = true;
  final armed = <String>{};
  for (final p in plans) {
    if (!p.valid || p.raw['remind'] != true) continue;
    for (final (index, c) in p.cheques().indexed) {
      for (final (slot, alarm) in chequeAlarmPlan(c, clock).indexed) {
        final key = 'plan:${p.id}:$index:$slot';
        armed.add(key);
        ok =
            await store.setReminder(
              key,
              sourceKind: 'plan',
              sourceId: p.id,
              at: alarm.at,
              title: chequeStrings.text(l10n, 'title'),
              body: chequeAlarmText(c, l10n, days: alarm.days),
            ) &&
            ok;
      }
    }
  }
  for (final alarm in existing) {
    final owner = RegExp(r'^plan:(.+):[0-9]+:[0-9]+$')
        .firstMatch(alarm.id)
        ?.group(1);
    if (owner != null &&
        (planId == null || owner == planId) &&
        !armed.contains(alarm.id)) {
      await store.withdrawReminder(alarm.id);
    }
  }
  return ok;
}

String chequeAlarmText(Cheque c, AppLocalizations l10n, {int days = 0}) {
  if (c.raw['privateAlert'] == true) {
    return chequeStrings.text(l10n, 'alarmBody');
  }
  final integer = int.tryParse(c.remaining.toString());
  final n = integer != null
      ? formatNumber(integer, l10n.localeName.startsWith('fa'))
      : c.remaining.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
  return chequeStrings.text(l10n, 'alarmNamed', {
    'party': c.party,
    'amount': nexDigits(n, persian: l10n.localeName.startsWith('fa')),
    'unit': chequeStrings.text(l10n, 'rial'),
    'when': chequeStrings.text(l10n, days == 0 ? 'today' : 'days', {'n': days}),
    'date': c.actionDay == null
        ? ''
        : nexReadableDate(
            c.actionDay!,
            persian: l10n.localeName.startsWith('fa'),
            solar: l10n.localeName.startsWith('fa'),
          ),
  });
}
