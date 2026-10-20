import 'package:nex_client/modules/module_api.dart';
import 'money_format.dart';
import 'number_input.dart';

/// One quit attempt: when it started, the baseline it is measured against,
/// and — for every attempt but the newest — when and why it ended.
///
/// Stored as kind `quit`. The active attempt is the one with no `endedAt`;
/// history is every attempt before it, kept forever: a lapse starts a new
/// attempt, it never rewrites an old one.
class QuitAttempt {
  const QuitAttempt({
    required this.id,
    required this.startedAt,
    required this.cigarettesPerDay,
    int? pricePerPackRials,
    int? pricePerPackMinor,
    this.currency = 'IRR',
    this.currencyDecimals,
    required this.perPack,
    required this.endedAt,
    required this.endedWhy,
  }) : pricePerPackMinor = pricePerPackMinor ?? pricePerPackRials ?? 0;

  factory QuitAttempt.fromRecord(ModuleRecord record) =>
      QuitAttempt.fromBody(record.id, record.body);

  factory QuitAttempt.fromBody(String id, Map<String, Object?> body) {
    int whole(Object? v) => safeWhole(v);
    // A missing pack size reads as the customary 20 — the value the setup
    // sheet offers by default — rather than as 1, which would silently
    // multiply every money estimate by twenty.
    final rawPerPack = body['perPack'];
    final perPack = rawPerPack is num && rawPerPack.isFinite
        ? rawPerPack.toInt().clamp(1, 100)
        : 20;
    return QuitAttempt(
      id: id,
      startedAt:
          DateTime.tryParse('${body['startedAt'] ?? ''}') ?? DateTime.now(),
      cigarettesPerDay: whole(body['cigarettesPerDay']).clamp(0, 1000),
      // Money is integer rials, always — never a double.
      pricePerPackMinor: whole(
        body['pricePerPackMinor'] ?? body['pricePerPackRials'],
      ).clamp(0, maxMoney),
      currency: currencyCode(body['currency']),
      currencyDecimals: moneyDigits(
        currencyCode(body['currency']),
        body['currencyDecimals'],
      ),
      perPack: perPack,
      endedAt: body['endedAt'] is String
          ? DateTime.tryParse(body['endedAt'] as String)
          : null,
      endedWhy: body['endedWhy'] is String ? body['endedWhy'] as String : null,
    );
  }

  final String id;

  /// When this attempt began — a local instant, stored as ISO 8601.
  final DateTime startedAt;

  /// How many cigarettes a day the person smoked before quitting. The
  /// estimate basis, said out loud on the dashboard.
  final int cigarettesPerDay;

  /// The price of one pack, in the currency's integer minor units.
  final int pricePerPackMinor;
  final String currency;
  final int? currencyDecimals;
  int get digits => moneyDigits(currency, currencyDecimals);

  /// Cigarettes in a pack; 20 unless the person said otherwise.
  final int perPack;

  /// When this attempt ended (a lapse, or a deliberate restart); null while
  /// it is running.
  final DateTime? endedAt;

  /// `lapse` or `restart`, when it is over.
  final String? endedWhy;

  bool get isActive => endedAt == null;

  Map<String, Object?> toJson({DateTime? endedAt, String? endedWhy}) => {
    'startedAt': startedAt.toIso8601String(),
    'cigarettesPerDay': cigarettesPerDay,
    'v': 2,
    'pricePerPackMinor': pricePerPackMinor,
    if (currency == 'IRR') 'pricePerPackRials': pricePerPackMinor,
    'currency': currency,
    'currencyDecimals': digits,
    'perPack': perPack,
    'endedAt': (endedAt ?? this.endedAt)?.toIso8601String(),
    'endedWhy': endedWhy ?? this.endedWhy,
  };
}

/// One craving, logged in a tap: when it was, how strong, what triggered it,
/// what the person did about it — and nothing else. Stored as kind
/// `craving`.
class Craving {
  const Craving({
    required this.id,
    required this.at,
    required this.intensity,
    required this.triggers,
    required this.coping,
    required this.note,
  });

  factory Craving.fromRecord(ModuleRecord record) =>
      Craving.fromBody(record.id, record.body);

  factory Craving.fromBody(String id, Map<String, Object?> body) {
    return Craving(
      id: id,
      at: DateTime.tryParse('${body['at'] ?? ''}') ?? DateTime.now(),
      // 1 low, 2 medium, 3 high; anything else reads as low rather than
      // crashing a list.
      intensity: body['intensity'] is num
          ? ((body['intensity'] as num).isFinite
                ? (body['intensity'] as num).clamp(1, 3).toInt()
                : 1)
          : 1,
      triggers: {
        for (final t
            in body['triggers'] is List ? body['triggers'] as List : const [])
          if (t is String && cravingTriggerKeys.contains(t)) t,
      }.toList(),
      coping: cravingCopingKeys.contains(body['coping'])
          ? body['coping'] as String
          : null,
      note: body['note'] is String ? body['note'] as String : '',
    );
  }

  final String id;

  /// When the craving happened.
  final DateTime at;

  final int intensity;

  /// Zero or more of the known trigger keys.
  final List<String> triggers;

  /// The coping key, when one was chosen.
  final String? coping;

  /// A free short note, possibly empty.
  final String note;

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'intensity': intensity,
    'triggers': triggers,
    'coping': coping,
    'note': note,
  };
}

/// The trigger vocabulary, fixed keys with localized labels. A craving's
/// `triggers` hold keys; the screen says the words.
const List<String> cravingTriggerKeys = [
  'stress',
  'boredom',
  'coffee',
  'afterMeal',
  'social',
  'driving',
  'tired',
  'emotion',
  'other',
];

/// The coping vocabulary, the same way.
const List<String> cravingCopingKeys = [
  'water',
  'deepBreath',
  'walk',
  'gum',
  'waited',
  'distraction',
];
