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
}) async {
  final plan = chequeAlarmPlan(c, now ?? DateTime.now());
  var ok = true;
  for (final d in [0, 1, 3, 7, 14, 30]) {
    final matching = plan.where((a) => a.days == d);
    final key = chequeAlarmKey(c.id, d);
    if (matching.isEmpty) {
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
            at: matching.first.at,
            title: chequeStrings.text(l10n, 'title'),
            body: chequeAlarmText(c, l10n, days: d),
          ) &&
          ok;
    }
  }
  return ok;
}

Future<void> renewCheques(NexModuleStore store, AppLocalizations l10n) async {
  await renewPlans(store, l10n);
  for (final row in await store.list('cheque')) {
    await armCheque(store, Cheque(row.id, row.body), l10n, upkeep: true);
  }
}

Future<bool> renewPlans(NexModuleStore store, AppLocalizations l10n) async {
  var ok = true;
  final validKeys = <String>{};
  for (final row in await store.list('plan')) {
    final p = InstalmentPlan(row.id, row.body);
    if (!p.valid) continue;
    for (final c in p.cheques()) {
      final index = c.id.split(':').last;
      final plan = chequeAlarmPlan(c, DateTime.now());
      for (var slot = 0; slot < 2; slot++) {
        final key = 'plan:${p.id}:$index:$slot';
        validKeys.add(key);
        if (slot >= plan.length) {
          await store.withdrawReminder(key);
        } else {
          ok =
              await store.setReminder(
                key,
                sourceKind: 'plan',
                sourceId: p.id,
                at: plan[slot].at,
                title: chequeStrings.text(l10n, 'title'),
                body: chequeAlarmText(c, l10n, days: plan[slot].days),
              ) &&
              ok;
        }
      }
    }
  }
  for (final alarm in await store.list('__reminder')) {
    if (alarm.id.startsWith('plan:') && !validKeys.contains(alarm.id)) {
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
