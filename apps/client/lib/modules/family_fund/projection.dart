import 'package:nex_client/modules/module_api.dart';

import 'model.dart';

class ModuleSummary {
  const ModuleSummary(this.title, this.detail, {required this.private});
  final String title;
  final String? detail;
  final bool private;
}

ModuleSummary? summarize(ModuleRecord record) {
  final fund = Fund.read(record);
  return fund == null ? null : ModuleSummary(fund.name, null, private: true);
}

class ModuleDue {
  const ModuleDue(
    this.id,
    this.recordId,
    this.at,
    this.title,
    this.kind,
    this.amountRial,
    this.done,
  );
  final String id, recordId, title, kind;
  final DateTime at;
  final int? amountRial;
  final bool done;
  String get recordKind => 'fund';
  bool get private => true;
}

class FundDues {
  const FundDues(this.fund);
  final Fund fund;
  List<ModuleDue> forMonth(NexModuleMonth month) {
    final key = dayKey(month.first);
    final drawDone = fund.winner(month) != null;
    return [
      if (!month.first.isBefore(fund.start.first)) ...[
        for (final m in fund.active(month))
          ModuleDue(
            'payment:${fund.id}:$key:${m['id']}',
            fund.id,
            dueDay(month, fund.paymentDay),
            nameOf(m),
            'fund-contribution',
            fund.shareRial * (m['shares'] as int),
            fund.payment(month, m['id']) != null,
          ),
        ModuleDue(
          'draw:${fund.id}:$key',
          fund.id,
          dueDay(month, fund.drawDay),
          fund.name,
          'fund-draw',
          null,
          drawDone,
        ),
      ],
      for (final l in fund.loans)
        for (final (i, part) in rows(l['instalments']).indexed)
          if (fundMonth(DateTime.parse(part['due'] as String)) == month)
            ModuleDue(
              'instalment:${fund.id}:${l['draw']}:$i',
              fund.id,
              DateTime.parse(part['due'] as String),
              nameOf(l),
              'fund-instalment',
              part['amountRial'] as int,
              part['paidAt'] != null,
            ),
    ];
  }

  List<ModuleDue> duesBetween(DateTime from, DateTime to) {
    final lower = dayKey(from), upper = dayKey(to);
    if (lower.compareTo(upper) > 0) return [];
    final end = fundMonth(to);
    final result = <ModuleDue>[];
    for (
      var month = fundMonth(from);
      !month.first.isAfter(end.first);
      month = month.shift(1)
    ) {
      result.addAll(
        forMonth(month).where(
          (due) =>
              dayKey(due.at).compareTo(lower) >= 0 &&
              dayKey(due.at).compareTo(upper) <= 0,
        ),
      );
    }
    return result..sort((a, b) => a.at.compareTo(b.at));
  }
}
