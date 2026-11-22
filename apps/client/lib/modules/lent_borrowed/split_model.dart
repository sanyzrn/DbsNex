import 'package:nex_client/modules/module_api.dart';

import 'loan_model.dart';
import 'loan_people.dart';
import 'money_format.dart';
import 'number_input.dart';

/// How one cost is divided between the people who share it.
enum SplitMode {
  equal,
  shares,
  amounts;

  String get key => switch (this) {
    SplitMode.equal => 'equal',
    SplitMode.shares => 'shares',
    SplitMode.amounts => 'amounts',
  };

  static SplitMode fromKey(Object? raw) {
    if (raw == 'shares') return SplitMode.shares;
    if (raw == 'amounts') return SplitMode.amounts;
    return SplitMode.equal;
  }
}

/// One cost inside a split: what it was, what it cost, who paid, and how the
/// people sharing it divide it. Stored inside the split's own record, so a
/// split reads and writes as one thing — never half a trip.
class SplitCost {
  const SplitCost({
    required this.id,
    required this.title,
    required this.amount,
    required this.payer,
    required this.mode,
    required this.parts,
  });

  factory SplitCost.fromBody(Object? raw) {
    final body = raw is Map ? raw : const <Object?, Object?>{};
    final mode = SplitMode.fromKey(body['mode']);
    final parts = <String, int>{};
    final rawParts = body['parts'];
    if (rawParts is Map) {
      for (final MapEntry(:key, :value) in rawParts.entries) {
        if (key is! String || key.trim().isEmpty) continue;
        final number = safeWhole(value);
        if (mode != SplitMode.equal && number <= 0) continue;
        parts[key.trim()] = number;
      }
    }
    return SplitCost(
      id: body['id'] is String ? body['id'] as String : '',
      title: body['title'] is String ? (body['title'] as String).trim() : '',
      amount: safeWhole(body['amount']).clamp(0, maxMoney),
      payer: body['payer'] is String ? (body['payer'] as String).trim() : '',
      mode: mode,
      parts: parts,
    );
  }

  final String id;
  final String title;
  final int amount;
  final String payer;
  final SplitMode mode;

  /// Who shares this cost, and — for [SplitMode.shares] and
  /// [SplitMode.amounts] — their weight or exact amount. For
  /// [SplitMode.equal] only the names matter.
  final Map<String, int> parts;

  bool get usable =>
      amount > 0 &&
      payer.trim().isNotEmpty &&
      parts.isNotEmpty &&
      (mode != SplitMode.amounts ||
          parts.values.fold(0, (a, b) => a + b) == amount);

  SplitCost copyWith({
    String? id,
    String? title,
    int? amount,
    String? payer,
    SplitMode? mode,
    Map<String, int>? parts,
  }) => SplitCost(
    id: id ?? this.id,
    title: title ?? this.title,
    amount: amount ?? this.amount,
    payer: payer ?? this.payer,
    mode: mode ?? this.mode,
    parts: parts ?? this.parts,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'payer': payer,
    'mode': mode.key,
    'parts': parts,
  };
}

/// A split: a trip, a shared month, a party — several costs between the same
/// people, and who pays whom to make it even again.
class LoanSplit {
  const LoanSplit({
    required this.id,
    required this.title,
    required this.date,
    required this.me,
    required this.people,
    required this.costs,
  });

  factory LoanSplit.fromRecord(ModuleRecord record) =>
      LoanSplit.fromBody(record.id, record.body);

  factory LoanSplit.fromBody(String id, Map<String, Object?> body) {
    final people = <String>[];
    final keys = <String>{};
    for (final raw in body['people'] is List ? body['people']! as List : []) {
      if (raw is! String) continue;
      final name = raw.trim();
      if (name.isEmpty || !keys.add(personKey(name))) continue;
      people.add(name);
    }
    final costs = <SplitCost>[];
    for (final raw in body['costs'] is List ? body['costs']! as List : []) {
      costs.add(SplitCost.fromBody(raw));
    }
    final date =
        _civilKey('${body['date'] ?? ''}') ?? civilDateKey(DateTime.now());
    return LoanSplit(
      id: id,
      title: body['title'] is String ? (body['title'] as String).trim() : '',
      date: date,
      me: body['me'] is String ? (body['me'] as String).trim() : '',
      people: people,
      costs: costs.where((cost) => cost.amount > 0).toList(),
    );
  }

  final String id;
  final String title;
  final String date;

  /// Which participant is the person holding the phone. Empty when the
  /// record was written without one: transfers then stay informational.
  final String me;
  final List<String> people;
  final List<SplitCost> costs;

  /// The sum of every cost, in rials.
  int get total => costs.fold(0, (sum, cost) => sum + cost.amount);

  LoanSplit copyWith({
    String? title,
    String? date,
    String? me,
    List<String>? people,
    List<SplitCost>? costs,
  }) => LoanSplit(
    id: id,
    title: title ?? this.title,
    date: date ?? this.date,
    me: me ?? this.me,
    people: people ?? this.people,
    costs: costs ?? this.costs,
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'title': title,
    'date': date,
    'me': me,
    'people': people,
    'costs': [for (final cost in costs) cost.toJson()],
  };
}

/// The ids new costs get: the time in microseconds, so two costs added in
/// the same session never collide and an old one is never reused.
String newSplitCostId() => 'c${DateTime.now().microsecondsSinceEpoch}';

/// A stored civil day, or null when it is not one.
String? _civilKey(String raw) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || civilDateKey(parsed) != raw) return null;
  return raw;
}
