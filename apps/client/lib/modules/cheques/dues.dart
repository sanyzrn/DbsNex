import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'plan_model.dart';

/// Temporary local copy of the exact contract in docs/18, rule 1.
class ModuleDue {
  const ModuleDue({
    required this.id,
    required this.recordKind,
    required this.recordId,
    required this.at,
    required this.title,
    required this.kind,
    required this.amountRial,
    required this.done,
    required this.private,
  });
  final String id, recordKind, recordId, title, kind;
  final DateTime at;
  final int? amountRial;
  final bool done, private;
}

/// An immutable snapshot. No storage, locale, widgets, clock or permissions.
class ChequeDues {
  ChequeDues(Iterable<Cheque> rows) : rows = List.unmodifiable(rows);
  factory ChequeDues.fromRecords(Iterable<ModuleRecord> records) => ChequeDues([
    for (final r in records.where((r) => r.module == 'cheques'))
      if (r.kind == 'cheque')
        Cheque(r.id, r.body)
      else if (r.kind == 'plan')
        ...InstalmentPlan(r.id, r.body).cheques(),
  ]);
  final List<Cheque> rows;

  /// Inclusive civil days. Time-of-day is ignored, without converting to UTC.
  List<ModuleDue> duesBetween(DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day),
        end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) return [];
    final result = <ModuleDue>[];
    for (final c in rows) {
      final at = c.actionDay;
      if (!c.valid || at == null || at.isBefore(start) || at.isAfter(end)) {
        continue;
      }
      final review = c.purpose == 'guarantee';
      // A closed/returned/transferred cheque does not promise a cash receipt.
      final money = review
          ? null
          : c.closed
          ? BigInt.zero
          : c.remaining;
      final signed = money == null
          ? null
          : c.direction == 'incoming'
          ? money
          : -money;
      result.add(
        ModuleDue(
          id: c.recordKind == 'plan' ? c.id : 'cheque:${c.id}',
          recordKind: c.recordKind,
          recordId: c.recordId,
          at: at,
          title: c.party,
          kind: review
              ? 'cheque-review'
              : c.recordKind == 'plan'
              ? 'instalment'
              : c.direction == 'incoming'
              ? 'cheque-in'
              : 'cheque-out',
          // Legacy 24-digit values stay exact in storage and local totals. Never
          // saturate/toInt() them into a false value for the shared int contract.
          amountRial: signed == null ? null : int.tryParse(signed.toString()),
          done: c.closed,
          private: true,
        ),
      );
    }
    return result..sort((a, b) {
      final day = a.at.compareTo(b.at);
      return day == 0 ? a.id.compareTo(b.id) : day;
    });
  }
}
