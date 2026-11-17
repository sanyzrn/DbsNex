import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'values.dart';

class InstalmentPlan {
  InstalmentPlan(this.id, this.raw);
  final String id;
  final Map<String, Object?> raw;
  String get title => raw['title'] is String ? raw['title'] as String : '';
  int get count => raw['count'] is int ? raw['count'] as int : 0;
  int get months => raw['months'] is int ? raw['months'] as int : 0;
  BigInt? get total => chequeAmount(raw['totalRial']);
  DateTime? get first => chequeDay(raw['first']);
  bool get valid =>
      raw['v'] == 1 &&
      title.trim().isNotEmpty &&
      title.length <= 100 &&
      count > 0 &&
      count <= 120 &&
      months > 0 &&
      months <= 12 &&
      total != null &&
      total! >= BigInt.from(count) &&
      first != null &&
      ['jalali', 'gregorian'].contains(raw['calendar']) &&
      raw['remind'] is bool &&
      raw['beforeDays'] is int &&
      (raw['beforeDays'] as int) > 0 &&
      (raw['beforeDays'] as int) <= 30 &&
      raw['minutes'] is int &&
      (raw['minutes'] as int) >= 0 &&
      (raw['minutes'] as int) < 1440 &&
      raw['paid'] is Map &&
      (raw['paid'] as Map).entries.every(
        (e) =>
            e.key is String &&
            int.tryParse(e.key as String) != null &&
            int.parse(e.key as String) >= 0 &&
            int.parse(e.key as String) < count &&
            chequeDay(e.value) != null,
      );
  DateTime date(int i) {
    if (!valid || i < 0 || i >= count) throw const FormatException('plan');
    final start = first!;
    if (raw['calendar'] == 'jalali') {
      final p = nexPersianDate(start),
          m = p.month - 1 + i * months,
          y = p.year + m ~/ 12,
          month = m % 12 + 1;
      return nexGregorianDate(
        y,
        month,
        p.day.clamp(1, nexPersianMonthDays(y, month)),
      );
    }
    final m = start.month - 1 + i * months,
        y = start.year + m ~/ 12,
        month = m % 12 + 1;
    return DateTime(
      y,
      month,
      start.day.clamp(1, DateTime(y, month + 1, 0).day),
    );
  }

  BigInt amount(int i) =>
      total! ~/ BigInt.from(count) +
      (i == count - 1 ? total! % BigInt.from(count) : BigInt.zero);
  bool paid(int i) => (raw['paid'] as Map).containsKey('$i');
  List<Cheque> cheques() => !valid
      ? []
      : [
          for (var i = 0; i < count; i++)
            Cheque(
              'plan:$id:$i',
              {
                'v': 1,
                'direction': 'outgoing',
                'purpose': 'payment',
                'amountRial': amount(i).toString(),
                'unit': 'rial',
                'party': '$title · ${i + 1}/$count',
                'bank': '',
                'account': '',
                'number': '',
                'sayad': '',
                'note': '',
                'due': chequeDayKey(date(i)),
                'followUp': '',
                'status': paid(i) ? 'settled' : 'active',
                'events': paid(i)
                    ? [
                        {
                          'id': 'payment',
                          'kind': 'payment',
                          'previous': 'active',
                          'next': 'settled',
                          'day': (raw['paid'] as Map)['$i'],
                          'amountRial': amount(i).toString(),
                          'note': '',
                          'target': '',
                          'voided': false,
                        },
                      ]
                    : <Object?>[],
                'sayadState': 'unknown',
                'remind': raw['remind'] == true,
                'reminderDays': [raw['beforeDays'] ?? 3, 0],
                'minutes': raw['minutes'] ?? 540,
              },
              recordKind: 'plan',
              recordId: id,
            ),
        ];
}
