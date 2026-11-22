import 'package:nex_client/modules/module_api.dart';

import 'model.dart';

ModuleSummary? summarize(ModuleRecord record) {
  final fund = Fund.read(record);
  return fund == null ? null : ModuleSummary(title: fund.name, private: true);
}

class FundDues {
  const FundDues(this.fund);
  final Fund fund;
  List<ModuleDue> forMonth(NexModuleMonth month) {
    final key = dayKey(month.first);
    final drawDone = fund.winner(month) != null;
    final share = fund.shareFor(month);
    final active = month.first.isBefore(fund.start.first)
        ? const <Fields>[]
        : fund.active(month);
    return [
      if (active.isNotEmpty) ...[
        for (final m in active) _contribution(month, key, m, share),
        ModuleDue(
          id: 'draw:${fund.id}:$key',
          recordKind: 'fund',
          recordId: fund.id,
          at: dueDay(month, fund.drawDay),
          title: fund.name,
          kind: 'fund-draw',
          amountRial: null,
          done: drawDone,
          private: true,
        ),
      ],
      for (final l in fund.loans)
        for (final (i, part) in rows(l['instalments']).indexed)
          if (fundMonth(DateTime.parse(part['due'] as String)) == month)
            ModuleDue(
              id: 'instalment:${fund.id}:${l['draw']}:$i',
              recordKind: 'fund',
              recordId: fund.id,
              at: DateTime.parse(part['due'] as String),
              title: nameOf(l),
              kind: 'fund-instalment',
              amountRial: part['amountRial'] as int,
              done: part['paidAt'] != null,
              private: true,
            ),
    ];
  }

  ModuleDue _contribution(
    NexModuleMonth month,
    String key,
    Fields member,
    int share,
  ) {
    final payment = fund.payment(month, member['id']);
    return ModuleDue(
      id: 'payment:${fund.id}:$key:${member['id']}',
      recordKind: 'fund',
      recordId: fund.id,
      at: dueDay(month, fund.paymentDay),
      title: nameOf(member),
      kind: 'fund-contribution',
      amountRial: payment == null
          ? share * (member['shares'] as int)
          : payment['amountRial'] as int,
      done: payment != null,
      private: true,
    );
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
