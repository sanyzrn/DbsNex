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
bool between(Object? value, int low, int high) =>
    value is int && value >= low && value <= high;

/// What a month's share has come to, after every change recorded for it and
/// earlier months. A change is written only when the amount differs.
class Fund {
  Fund(this.id, this.body);
  final String id;
  final Fields body;
  String get name => body['name'] as String;
  String get rules => body['rules'] as String;

  /// The share the fund opened with. Later amounts live in [shareChanges];
  /// read the share of a month through [shareFor], never this directly.
  int get shareRial => body['shareRial'] as int;
  int get paymentDay => body['paymentDay'] as int;
  int get drawDay => body['drawDay'] as int;
  NexModuleMonth get start =>
      fundMonth(DateTime.parse(body['start'] as String));
  List<Fields> get members => rows(body['members']);
  List<Fields> get payments => rows(body['payments']);
  List<Fields> get draws => rows(body['draws']);
  List<Fields> get loans => rows(body['loans']);

  /// `{from: ISO first of a Jalali month, shareRial: int}`, oldest first.
  /// Optional: a fund that has never changed its share has no list at all,
  /// and records written before share changes existed read the same way.
  List<Fields> get shareChanges {
    final raw = body['shareChanges'];
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map) row.cast<String, Object?>(),
    ];
  }

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
          !_monthDay(f.body['start']) ||
          f.start.year < 1300 ||
          f.start.year > 1499) {
        return null;
      }
      final shareStarts = <String>{};
      for (final change in f.shareChanges) {
        final from = change['from'], amount = change['shareRial'];
        if (!_monthDay(from) ||
            !_share(amount) ||
            !shareStarts.add(from as String) ||
            (from).compareTo(dayKey(f.start.first)) < 0) {
          return null;
        }
      }
      final ids = <String>{};
      for (final m in f.members) {
        if (!ids.add(m['id'] as String) ||
            nameOf(m).trim().isEmpty ||
            (m['shares'] as int) < 1 ||
            (m['shares'] as int) > 100 ||
            !_monthDay(m['from']) ||
            (m['until'] != null && !_monthDay(m['until']))) {
          return null;
        }
      }
      final keys = <(Object?, Object?)>{};
      for (final p in f.payments) {
        if (!ids.contains(p['member']) ||
            !_monthDay(p['month']) ||
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
            !_monthDay(d['month']) ||
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

  /// A stored month is always the first day of its Jalali month. A value
  /// in the middle of a month would look for a payment in a month that can
  /// never be found again.
  static bool _monthDay(Object? raw) =>
      _day(raw) &&
      dayKey(fundMonth(DateTime.parse(raw as String)).first) == raw;

  static bool _amount(Object? raw) =>
      raw is int && raw > 0 && raw <= 100000000000000;

  static bool _share(Object? raw) =>
      raw is int && raw > 0 && raw <= 100000000000;

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
  Fields? loanFor(Object? draw) =>
      loans.where((l) => l['draw'] == draw).firstOrNull;

  /// The share of [month]: the latest change at or before its first day,
  /// else the amount the fund opened with.
  int shareFor(NexModuleMonth month) {
    final key = dayKey(month.first);
    var share = shareRial;
    var from = '';
    for (final change in shareChanges) {
      final at = change['from'] as String;
      if (at.compareTo(key) <= 0 && at.compareTo(from) >= 0) {
        share = change['shareRial'] as int;
        from = at;
      }
    }
    return share;
  }

  /// What every active member's shares add up to this month: the pot that
  /// is gathered before a payout.
  int potFor(NexModuleMonth month) {
    if (month.first.isBefore(start.first)) return 0;
    final share = shareFor(month);
    return active(month)
        .fold(0, (sum, m) => sum + share * (m['shares'] as int));
  }

  /// Contributions recorded *for* [month], whenever they were received.
  int collectedFor(NexModuleMonth month) {
    final key = dayKey(month.first);
    return payments
        .where((p) => p['month'] == key)
        .fold(0, (sum, p) => sum + (p['amountRial'] as int));
  }

  /// The body with a new share from [from]. Recorded contributions keep the
  /// amounts they were saved with, so past months read exactly as before.
  ///
  /// Entries that repeat the amount already in force are dropped, and an
  /// entry's unknown fields are kept when it survives. The list is sorted,
  /// which gives [shareFor] one obvious order.
  Fields withShare(NexModuleMonth from, int newShareRial) {
    final startKey = dayKey(start.first);
    final wanted = dayKey(from.first).compareTo(startKey) < 0
        ? startKey
        : dayKey(from.first);
    final byStart = {
      for (final change in shareChanges) change['from'] as String: change,
    };
    byStart[wanted] = {
      ...?byStart[wanted],
      'from': wanted,
      'shareRial': newShareRial,
    };
    final starts =
        byStart.keys.where((key) => key.compareTo(startKey) >= 0).toList()
          ..sort();
    var previous = shareRial;
    final kept = <Fields>[];
    for (final key in starts) {
      final entry = byStart[key]!;
      final share = entry['shareRial'] as int;
      // A redundant amount is dropped unless the entry carries something the
      // model does not know about; future versions may add fields there.
      if (share == previous &&
          !entry.keys.any((k) => k != 'from' && k != 'shareRial')) {
        continue;
      }
      kept.add({...entry, 'from': key, 'shareRial': share});
      previous = share;
    }
    return {...body, 'shareChanges': kept};
  }

  /// Whether [candidate] leaves any day a recorded payout was made with less
  /// than zero cash — the one rule a correction or a removal may not break.
  bool keepsLedgerSound(Fields candidate) {
    try {
      final next = Fund(id, candidate);
      return next.loans.every(
        (l) => next.balanceAt(DateTime.parse(l['at'] as String)) >= 0,
      );
    } on Object {
      return false;
    }
  }

  /// Months from the member's join up to [now] whose contribution day has
  /// passed with nothing recorded. Used by the member sheet, not by money
  /// arithmetic.
  List<FundArrears> arrearsFor(Fields member, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final id = member['id'];
    final shares = member['shares'] as int;
    final from = fundMonth(DateTime.parse(member['from'] as String));
    final untilRaw = member['until'];
    final until = untilRaw == null
        ? null
        : fundMonth(DateTime.parse(untilRaw as String));
    final end = fundMonth(now);
    var month = from.first.isBefore(start.first) ? start : from;
    final result = <FundArrears>[];
    // A century of months is far beyond any family fund; the bound only
    // keeps a corrupt date from making a screen loop forever.
    for (
      var i = 0;
      i < 1200 && !month.first.isAfter(end.first);
      i++, month = month.shift(1)
    ) {
      if (month.first.isBefore(start.first)) continue;
      if (until != null && !month.first.isBefore(until.first)) continue;
      if (payment(month, id) != null) continue;
      final due = dueDay(month, paymentDay);
      if (!due.isBefore(today)) continue;
      result.add(
        FundArrears(
          month: month,
          due: due,
          amountRial: shareFor(month) * shares,
        ),
      );
    }
    return result;
  }

  /// Every effective win of [member], oldest first.
  List<Fields> winsFor(Object? member) => [
    for (final draw in effectiveDraws.values)
      if (draw['winner'] == member) draw,
  ]..sort((a, b) => (a['month'] as String).compareTo(b['month'] as String));

  /// Payments of [member], by fund month.
  List<Fields> paymentsFor(Object? member) =>
      payments.where((p) => p['member'] == member).toList()..sort(
        (a, b) => (a['month'] as String).compareTo(b['month'] as String),
      );

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

  /// Who has received the fund in the round in progress, and who is still
  /// waiting. A participant is every member active this month plus anyone
  /// who won this round and has since left; winners are the *effective*
  /// results, so a redraw replaces the attempt it superseded.
  FundRound roundFor(NexModuleMonth month) {
    final pool = drawPool(month);
    final number = pool.round;
    final winners =
        effectiveDraws.values.where((draw) => draw['round'] == number).toList()
          ..sort(
            (a, b) => (a['month'] as String).compareTo(b['month'] as String),
          );
    final winnerIds = winners.map((draw) => draw['winner']).toSet();
    final activeMembers = month.first.isBefore(start.first)
        ? const <Fields>[]
        : active(month);
    final byId = {for (final member in members) member['id']: member};
    final participants = <Fields>[...activeMembers];
    for (final id in winnerIds) {
      if (participants.any((m) => m['id'] == id)) continue;
      final member = byId[id];
      if (member != null) participants.add(member);
    }
    return FundRound(
      number: number,
      winners: winners,
      members: participants,
      remaining: participants
          .where((m) => !winnerIds.contains(m['id']))
          .toList(),
    );
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
    final picked = pool.eligible[random.nextInt(pool.eligible.length)];
    // Keep the pool for audit and redraws. Shares are part of the snapshot
    // too: the eligible list is a record of what was true that day, not a
    // view recomputed from later data.
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
          'winner': picked['id'],
          'eligible': pool.eligible
              .map(
                (m) => <String, Object?>{
                  'id': m['id'],
                  'person': m['person'],
                  'shares': m['shares'],
                },
              )
              .toList(),
        },
      ],
    };
  }
}

/// A contribution month that has passed without a recorded payment.
class FundArrears {
  const FundArrears({
    required this.month,
    required this.due,
    required this.amountRial,
  });
  final NexModuleMonth month;
  final DateTime due;
  final int amountRial;
}

/// The round in progress: its number, its effective winners and who is
/// still waiting for their turn.
class FundRound {
  const FundRound({
    required this.number,
    required this.winners,
    required this.members,
    required this.remaining,
  });
  final int number;
  final List<Fields> winners;
  final List<Fields> members;
  final List<Fields> remaining;
  int get received => winners.length;
  int get total => members.length;
  bool get complete => members.isNotEmpty && remaining.isEmpty;
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
