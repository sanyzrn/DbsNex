import 'money_format.dart';
import 'irr_unit.dart';

String chequeDigits(String text) {
  const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
  return text.split('').map((c) {
    final f = fa.indexOf(c), a = ar.indexOf(c);
    return f >= 0
        ? '$f'
        : a >= 0
        ? '$a'
        : c;
  }).join();
}

/// Accept grouped identifiers copied from bank messages and Persian keyboards.
String normalizedSayad(String text) => chequeDigits(
  text,
).replaceAll(RegExp(r'[\s\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069-]'), '');

BigInt? chequeAmount(Object? raw) {
  if (raw is int) raw = raw.toString();
  if (raw is! String || !RegExp(r'^[1-9][0-9]{0,23}$').hasMatch(raw)) {
    return null;
  }
  return BigInt.tryParse(raw);
}

BigInt? enteredAmount(String text, String unit) {
  if (!['rial', 'toman'].contains(unit)) return null;
  final standard = parseAmount(text, 'IRR', 0, IrrUnit.fromKey(unit));
  if (standard != null) return standard > 0 ? BigInt.from(standard) : null;
  final value = chequeDigits(text.trim());
  // Only complete groups of three are accepted; no silently stripped symbols.
  if (!RegExp(r'^(?:[0-9]+|[0-9]{1,3}(?:[,٬][0-9]{3})+)$').hasMatch(value)) {
    return null;
  }
  final n = BigInt.tryParse(value.replaceAll(RegExp('[,٬]'), ''));
  if (n == null || n <= BigInt.zero || !['rial', 'toman'].contains(unit)) {
    return null;
  }
  final rial = unit == 'toman' ? n * BigInt.from(10) : n;
  return chequeAmount(rial.toString());
}

DateTime? chequeDay(Object? raw) {
  if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    return null;
  }
  final p = raw.split('-').map(int.parse).toList();
  if (p[0] < 1900 || p[0] > 2100) return null;
  final day = DateTime(p[0], p[1], p[2]);
  return day.year == p[0] && day.month == p[1] && day.day == p[2] ? day : null;
}

String chequeDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
int chequeDaysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

String amountForEdit(BigInt rial, String unit) {
  if (!['rial', 'toman'].contains(unit) ||
      rial < BigInt.zero ||
      (unit == 'toman' && rial % BigInt.from(10) != BigInt.zero)) {
    throw const FormatException('not a whole unit');
  }
  return (unit == 'toman' ? rial ~/ BigInt.from(10) : rial).toString();
}

/// Keep legacy large decimal strings exact; all representable new writes use integers.
Object storedRials(Object? raw) {
  final n = chequeAmount(raw);
  if (n == null) return raw ?? '';
  return n > BigInt.from(maxMoney) ? raw! : n.toInt();
}

/// New amounts use the reference's exact interoperable range. Existing larger
/// records remain editable unchanged; a full legacy settlement is still possible.
BigInt? editableAmount(String text, String unit, {BigInt? original}) {
  final amount = enteredAmount(text, unit);
  return amount != null &&
          (amount <= BigInt.from(maxMoney) || amount == original)
      ? amount
      : null;
}
