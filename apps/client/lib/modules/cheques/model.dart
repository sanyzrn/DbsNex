import 'values.dart';

const chequeStatuses = [
  'active',
  'registered',
  'handed',
  'deposited',
  'bounced',
  'settled',
  'transferred',
  'returned',
  'cancelled',
];
const chequeClosed = ['settled', 'transferred', 'returned', 'cancelled'];

class Cheque {
  Cheque(
    this.id,
    Map<String, Object?> body, {
    this.recordKind = 'cheque',
    String? recordId,
  }) : recordId = recordId ?? id,
       raw = Map.unmodifiable(body);
  final String recordKind, recordId;
  final String id;
  final Map<String, Object?> raw;
  String text(String key) => key == 'party'
      ? party
      : raw[key] is String
      ? raw[key] as String
      : '';
  String get party {
    final person = raw['person'];
    return person is Map && person['name'] is String
        ? person['name'] as String
        : raw['party'] is String
        ? raw['party'] as String
        : '';
  }

  String get direction => text('direction');
  String get purpose => text('purpose');
  String get status => text('status');
  String get unit => text('unit');
  String get sayad => text('sayad');
  BigInt? get face => chequeAmount(raw['amountRial']);
  DateTime? get due => chequeDay(raw['due']);
  DateTime? get followUp => chequeDay(raw['followUp']);
  DateTime? get actionDay => purpose == 'guarantee' ? followUp : due;
  bool get closed => chequeClosed.contains(status);
  List<Map<String, Object?>> get events => raw['events'] is List
      ? [
          for (final e in raw['events'] as List)
            if (e is Map)
              {
                for (final k in e.keys)
                  if (k is String) k: e[k],
              },
        ]
      : [];
  BigInt get paid => events
      .where((e) => e['kind'] == 'payment' && e['voided'] != true)
      .fold(
        BigInt.zero,
        (sum, e) => sum + (chequeAmount(e['amountRial']) ?? BigInt.zero),
      );
  BigInt get remaining => (face ?? BigInt.zero) - paid;
  bool get locked => events.any((e) => e['voided'] != true);
  bool get valid {
    if ([
      'bank',
      'account',
      'number',
      'sayad',
      'note',
      'direction',
      'purpose',
      'unit',
      'status',
      'sayadState',
      'due',
      'followUp',
    ].any((k) => raw[k] is! String)) {
      return false;
    }
    if (raw.containsKey('archived') && raw['archived'] != closed) return false;
    if (raw['sayadCheckedDay'] != null &&
        (raw['sayadCheckedDay'] is! String ||
            text('sayadCheckedDay').isNotEmpty &&
                chequeDay(raw['sayadCheckedDay']) == null)) {
      return false;
    }
    if (raw['v'] != 1 ||
        !['incoming', 'outgoing'].contains(direction) ||
        !['payment', 'guarantee'].contains(purpose) ||
        !['rial', 'toman'].contains(unit) ||
        face == null ||
        !chequeStatuses.contains(status) ||
        party.trim().isEmpty ||
        party.length > 100 ||
        text('bank').length > 100 ||
        text('account').length > 100 ||
        text('number').length > 60 ||
        text('note').length > 2000 ||
        !['unknown', 'todo', 'checked'].contains(text('sayadState')) ||
        (sayad.isNotEmpty && !RegExp(r'^[0-9]{16}$').hasMatch(sayad)) ||
        (purpose == 'payment' && due == null) ||
        (text('due').isNotEmpty && due == null) ||
        (text('followUp').isNotEmpty && followUp == null) ||
        raw['events'] is! List ||
        events.length != (raw['events'] as List).length ||
        events.length > 500) {
      return false;
    }
    final ids = <String>{};
    for (final e in events) {
      if (e['id'] is! String ||
          (e['id'] as String).isEmpty ||
          !ids.add(e['id'] as String) ||
          !['payment', 'status'].contains(e['kind']) ||
          chequeDay(e['day']) == null ||
          e['target'] is! String ||
          (e['target'] as String).length > 100 ||
          e['voided'] is! bool ||
          e['note'] is! String ||
          (e['note'] as String).length > 500 ||
          !chequeStatuses.contains(e['previous']) ||
          !chequeStatuses.contains(e['next']) ||
          (e['kind'] == 'payment' && chequeAmount(e['amountRial']) == null)) {
        return false;
      }
    }
    if (paid > (face ?? BigInt.zero) ||
        (status == 'settled' && remaining != BigInt.zero) ||
        (direction == 'outgoing' &&
            ['deposited', 'transferred'].contains(status)) ||
        (purpose == 'guarantee' &&
            (paid > BigInt.zero ||
                ['deposited', 'settled', 'transferred'].contains(status)))) {
      return false;
    }
    final active = events.where((e) => e['voided'] != true).toList();
    // A broken event chain is never treated as reliable financial data.
    var prior = 'active';
    var running = BigInt.zero;
    for (final e in active) {
      if (e['previous'] != prior) return false;
      if (e['kind'] == 'payment') {
        if (chequeClosed.contains(prior) || purpose != 'payment') return false;
        running += chequeAmount(e['amountRial'])!;
        if (running > face! ||
            e['next'] != (running == face ? 'settled' : prior)) {
          return false;
        }
      } else if (e['next'] == prior ||
          e['next'] == 'settled' ||
          (['deposited', 'transferred'].contains(e['next']) &&
              (direction != 'incoming' ||
                  purpose == 'guarantee' ||
                  (e['target'] as String).trim().isEmpty))) {
        return false;
      }
      prior = e['next'] as String;
    }
    if (prior != status || (!closed && paid == face)) return false;
    final days = raw['reminderDays'];
    return raw['remind'] is bool &&
        days is List &&
        days.length <= 3 &&
        days.every((d) => d is int && d >= 0 && d <= 30) &&
        days.toSet().length == days.length &&
        raw['minutes'] is int &&
        (raw['minutes'] as int) >= 0 &&
        (raw['minutes'] as int) < 1440 &&
        (raw['remind'] != true || (actionDay != null && days.isNotEmpty));
  }
}
