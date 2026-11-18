import 'dart:math';

import 'package:nex_client/modules/module_api.dart';

typedef Fields = Map<String, Object?>;
String dayKey(DateTime d) =>
    DateTime(d.year, d.month, d.day).toIso8601String().substring(0, 10);
NexModuleMonth fundMonth(DateTime day) => NexModuleMonth.of(day, solar: true);
DateTime dueDay(NexModuleMonth month, int day) =>
    month.dayAt(min(month.days, day));
List<Fields> rows(Object? value) => (value as List).cast<Fields>();
String nameOf(Fields row) => (row['person'] as Map)['name'] as String;

class Fund {
  Fund(this.id, this.body);
  final String id;
  final Fields body;
  String get name => body['name'] as String;
  String get rules => body['rules'] as String;
  int get shareRial => body['shareRial'] as int;
  int get paymentDay => body['paymentDay'] as int;
  int get drawDay => body['drawDay'] as int;
  NexModuleMonth get start =>
      fundMonth(DateTime.parse(body['start'] as String));
  List<Fields> get members => rows(body['members']);
  List<Fields> get payments => rows(body['payments']);
  List<Fields> get draws => rows(body['draws']);
  List<Fields> get loans => rows(body['loans']);

  static Fund? read(ModuleRecord record) {
    if (record.module != 'family_fund' || record.kind != 'fund') return null;
    try {
      final f = Fund(record.id, record.body);
      if (f.body['v'] != 1 ||
          f.name.trim().isEmpty ||
          f.rules.length > 3000 ||
          f.shareRial <= 0 ||
          f.shareRial > 100000000000 ||
          f.paymentDay < 1 ||
          f.paymentDay > 31 ||
          f.drawDay < 1 ||
          f.drawDay > 31 ||
          !_day(f.body['start']) ||
          f.start.year < 1300 ||
          f.start.year > 1499) {
        return null;
      }
      final ids = <String>{};
      for (final m in f.members) {
        if (!ids.add(m['id'] as String) ||
            nameOf(m).trim().isEmpty ||
            (m['shares'] as int) < 1 ||
            (m['shares'] as int) > 100 ||
            !_day(m['from']) ||
            (m['until'] != null && !_day(m['until']))) {
          return null;
        }
      }
      final keys = <(Object?, Object?)>{};
      for (final p in f.payments) {
        if (!ids.contains(p['member']) ||
            !_day(p['month']) ||
            !_day(p['at']) ||
            !_amount(p['amountRial']) ||
            !keys.add((p['member'], p['month']))) {
          return null;
        }
      }
      final drawIds = <String>{};
      for (final d in f.draws) {
        final pool = rows(d['eligible']);
        if (!drawIds.add(d['id'] as String) ||
            !ids.contains(d['winner']) ||
            !_day(d['month']) ||
            !_day(d['at']) ||
            (d['round'] as int) < 1 ||
            (d['reason'] is! String) ||
            !pool.any((p) => p['id'] == d['winner']) ||
            pool.any((p) => !ids.contains(p['id']) || nameOf(p).isEmpty)) {
          return null;
        }
      }
      final issued = <String>{};
      for (final l in f.loans) {
        if (!issued.add(l['draw'] as String) ||
            !drawIds.contains(l['draw']) ||
            nameOf(l).isEmpty ||
            !_day(l['at']) ||
            !_amount(l['amountRial'])) {
          return null;
        }
        var total = 0;
        for (final i in rows(l['instalments'])) {
          if (!_day(i['due']) ||
              !_amount(i['amountRial']) ||
              (i['paidAt'] != null && !_day(i['paidAt']))) {
            return null;
          }
          total += i['amountRial'] as int;
        }
        if (total != l['amountRial']) return null;
      }
      return f;
    } on Object {
      return null;
    }
  }

  static bool _day(Object? raw) {
    if (raw is! String) return false;
    final date = DateTime.tryParse(raw);
    return date != null && dayKey(date) == raw;
  }

  static bool _amount(Object? raw) =>
      raw is int && raw > 0 && raw <= 100000000000000;

  List<Fields> active(NexModuleMonth month) {
    final key = dayKey(month.first);
    return members
        .where(
          (m) =>
              (m['from'] as String).compareTo(key) <= 0 &&
              (m['until'] == null || (m['until'] as String).compareTo(key) > 0),
        )
        .toList();
  }

  Fields? payment(NexModuleMonth month, Object? member) => payments
      .where((p) => p['month'] == dayKey(month.first) && p['member'] == member)
      .firstOrNull;

  Map<String, Fields> get effectiveDraws => {
    for (final d in draws) d['month'] as String: d,
  };
  Fields? winner(NexModuleMonth month) => effectiveDraws[dayKey(month.first)];
  bool issued(Object? draw) => loans.any((l) => l['draw'] == draw);

  int balanceAt(DateTime date) {
    final key = dayKey(date);
    bool counted(Object? at) => at is String && at.compareTo(key) <= 0;
    return [
      for (final p in payments)
        if (counted(p['at'])) p['amountRial'] as int,
      for (final l in loans) ...[
        if (counted(l['at'])) -(l['amountRial'] as int),
        for (final i in rows(l['instalments']))
          if (counted(i['paidAt'])) i['amountRial'] as int,
      ],
    ].fold(0, (a, b) => a + b);
  }

  ({int round, List<Fields> eligible}) drawPool(NexModuleMonth month) {
    final last = draws.lastOrNull;
    final key = dayKey(month.first);
    if (last != null && (last['month'] as String).compareTo(key) > 0) {
      return (round: last['round'] as int, eligible: <Fields>[]);
    }
    if (winner(month) case final current?) {
      final used = draws
          .where((d) => d['month'] == key)
          .map((d) => d['winner'])
          .toSet();
      return (
        round: current['round'] as int,
        eligible: issued(current['id'])
            ? <Fields>[]
            : rows(current['eligible'])
                  .where((m) => !used.contains(m['id']))
                  .toList(),
      );
    }
    final round = last == null ? 1 : last['round'] as int;
    final won = effectiveDraws.values
        .where((d) => d['round'] == round)
        .map((d) => d['winner'])
        .toSet();
    final activeMembers = active(month);
    final available = activeMembers
        .where((m) => !won.contains(m['id']))
        .toList();
    return available.isEmpty && activeMembers.isNotEmpty
        ? (round: round + 1, eligible: activeMembers)
        : (round: round, eligible: available);
  }

  Fields draw(
    NexModuleMonth month,
    DateTime now,
    String id,
    String reason,
    Random random,
  ) {
    final pool = drawPool(month);
    if (pool.eligible.isEmpty ||
        month.first.isAfter(now) ||
        month.first.isBefore(start.first) ||
        (winner(month) != null && reason.trim().isEmpty)) {
      throw StateError('Invalid draw');
    }
    final winnerId = pool.eligible[random.nextInt(pool.eligible.length)]['id'];
    // Keep the original pool for later audit and redraws. Save the actual
    // eligible candidates separately on each attempt.
    return {
      ...body,
      'draws': [
        ...draws,
        <String, Object?>{
          'id': id,
          'month': dayKey(month.first),
          'at': dayKey(now),
          'round': pool.round,
          'reason': reason.trim(),
          'winner': winnerId,
          'eligible': pool.eligible
              .map(
                (m) => <String, Object?>{'id': m['id'], 'person': m['person']},
              )
              .toList(),
        },
      ],
    };
  }
}

List<Fields> instalments(
  int amountRial,
  int count,
  NexModuleMonth first,
  int day,
) {
  if (count < 1 || count > 60 || amountRial < count) {
    throw StateError('Invalid instalments');
  }
  final regular = amountRial ~/ count;
  return [
    for (var i = 0; i < count; i++)
      <String, Object?>{
        'amountRial': i == count - 1 ? amountRial - regular * i : regular,
        'due': dayKey(dueDay(first.shift(i), day)),
      },
  ];
}
