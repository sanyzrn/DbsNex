import 'irr_unit.dart';

/// A number said in words, in both languages.
///
/// The module shows every amount twice — as digits and as words — because a
/// misplaced zero is the mistake people actually make with money, and the
/// words catch it at a glance. The rules below are the ones a Persian
/// speaker reads by (Mace and Lambton's grammars, checked 2026-11-15):
///
/// - hundreds, tens and units are joined with «و»: ۳۴۵ = «سیصد و چهل و پنج»;
/// - the groups are joined with «و» as well, largest first:
///   ۱٬۲۰۰٬۰۰۰ = «یک میلیون و دویست هزار»;
/// - ۱۰۰ is «صد» and ۱٬۰۰۰ is «هزار», without «یک»; ۱۰⁶ and above keep it:
///   «یک میلیون», «یک میلیارد»;
/// - ۱۰¹² is «هزار میلیارد» — «تریلیون» is bookish and «بیلیون» reads as
///   either 10⁹ or 10¹², so neither is used.
///
/// English uses its short scale (thousand, million, billion, trillion), which
/// is what an English reader expects next to a currency code.
const _faUnits = [
  '',
  'یک',
  'دو',
  'سه',
  'چهار',
  'پنج',
  'شش',
  'هفت',
  'هشت',
  'نه',
  'ده',
  'یازده',
  'دوازده',
  'سیزده',
  'چهارده',
  'پانزده',
  'شانزده',
  'هفده',
  'هجده',
  'نوزده',
];

const _faTens = [
  '',
  '',
  'بیست',
  'سی',
  'چهل',
  'پنجاه',
  'شصت',
  'هفتاد',
  'هشتاد',
  'نود',
];

const _faHundreds = [
  '',
  'صد',
  'دویست',
  'سیصد',
  'چهارصد',
  'پانصد',
  'ششصد',
  'هفتصد',
  'هشتصد',
  'نهصد',
];

/// Persian group names, by group index (each group is three digits).
const _faScales = [
  '',
  'هزار',
  'میلیون',
  'میلیارد',
  'هزار میلیارد',
  'میلیون میلیارد',
];

const _enUnits = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];

const _enTens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

const _enScales = ['', 'thousand', 'million', 'billion', 'trillion'];

/// [value] in Persian words. Values below [maxMoney] (about 9×10¹⁵) are
/// covered; anything larger is refused rather than said wrongly.
String persianNumberWords(int value) {
  if (value < 0) return '−${persianNumberWords(-value)}';
  if (value == 0) return 'صفر';
  if (value > 999999999999999999) throw ArgumentError.value(value);
  final groups = <String>[];
  var rest = value;
  var index = 0;
  while (rest > 0) {
    final group = rest % 1000;
    if (group != 0) {
      final scale = _faScales[index];
      final words = _faUnder1000(group);
      // «هزار» and «هزار میلیارد» stand alone; «میلیون» and «میلیارد» take
      // «یک», as a person says them.
      if (group == 1 && (index == 1 || index == 4 || index == 5)) {
        groups.insert(0, scale);
      } else if (index >= 1) {
        groups.insert(0, '$words $scale');
      } else {
        groups.insert(0, words);
      }
    }
    rest ~/= 1000;
    index++;
  }
  return groups.join(' و ');
}

String _faUnder1000(int value) {
  if (value == 0) return '';
  final parts = <String>[];
  final hundred = value ~/ 100;
  final rest = value % 100;
  if (hundred > 0) parts.add(_faHundreds[hundred]);
  if (rest == 0) return parts.join(' و ');
  if (rest < 20) {
    parts.add(_faUnits[rest]);
  } else {
    parts.add(_faTens[rest ~/ 10]);
    if (rest % 10 != 0) parts.add(_faUnits[rest % 10]);
  }
  return parts.join(' و ');
}

/// [value] in English words, short scale.
String englishNumberWords(int value) {
  if (value < 0) return 'minus ${englishNumberWords(-value)}';
  if (value == 0) return 'zero';
  if (value > 999999999999999999) throw ArgumentError.value(value);
  final groups = <String>[];
  var rest = value;
  var index = 0;
  while (rest > 0) {
    final group = rest % 1000;
    if (group != 0) {
      final scale = _enScales[index];
      final words = _enUnder1000(group);
      groups.insert(0, index == 0 ? words : '$words $scale');
    }
    rest ~/= 1000;
    index++;
  }
  return groups.join(' ');
}

String _enUnder1000(int value) {
  if (value == 0) return '';
  if (value < 20) return _enUnits[value];
  if (value < 100) {
    final unit = value % 10;
    return unit == 0
        ? _enTens[value ~/ 10]
        : '${_enTens[value ~/ 10]}-${_enUnits[unit]}';
  }
  final rest = value % 100;
  final head = '${_enUnits[value ~/ 100]} hundred';
  return rest == 0 ? head : '$head ${_enUnder1000(rest)}';
}

/// «یک میلیون و دویست هزار تومان» — [minor] said in words in [unit].
///
/// [digits] is the currency's own precision, and [unit] is the word the
/// reader says for it («تومان», «ریال», "dollar"). A fraction is said as
/// tenths/hundredths of the unit, never dropped: the words must add up to
/// exactly what is stored.
String amountInWords({
  required int minor,
  required int digits,
  required bool persian,
  required String unit,
  String? unitOne,
}) {
  final factor = _pow10(digits);
  final whole = minor ~/ factor;
  final fraction = minor % factor;
  final words = persian ? persianNumberWords(whole) : englishNumberWords(whole);
  final one = unitOne ?? unit;
  final label = whole == 1 ? one : unit;
  final said = '$words $label';
  if (fraction == 0) return said;
  final fractionWords = persian
      ? persianNumberWords(fraction)
      : englishNumberWords(fraction);
  final name = switch (digits) {
    1 => persian ? 'دهم' : 'tenths',
    2 => persian ? 'صدم' : 'hundredths',
    3 => persian ? 'هزارم' : 'thousandths',
    _ => persian ? 'ده‌هزارم' : 'ten-thousandths',
  };
  return persian
      ? '$said و $fractionWords $name'
      : '$said and $fractionWords $name';
}

int _pow10(int power) {
  var value = 1;
  for (var i = 0; i < power; i++) {
    value *= 10;
  }
  return value;
}

/// The word a reader says for [currency] — «تومان» and «ریال» rather than a
/// Latin code on the Persian side, and the everyday English name otherwise.
/// An unknown code is said as itself; nothing is guessed.
String currencyUnitWord(
  String currency,
  IrrUnit irrUnit, {
  required bool persian,
  bool plural = true,
}) {
  final names = switch (currency) {
    'IRR' =>
      persian
          ? (irrUnit == IrrUnit.toman ? ('تومان', 'تومان') : ('ریال', 'ریال'))
          : (irrUnit == IrrUnit.toman
                ? ('toman', 'tomans')
                : ('rial', 'rials')),
    'USD' => persian ? ('دلار', 'دلار') : ('dollar', 'dollars'),
    'EUR' => persian ? ('یورو', 'یورو') : ('euro', 'euros'),
    'GBP' => persian ? ('پوند', 'پوند') : ('pound', 'pounds'),
    'AED' => persian ? ('درهم', 'درهم') : ('dirham', 'dirhams'),
    'JPY' => persian ? ('ین', 'ین') : ('yen', 'yen'),
    'KWD' =>
      persian
          ? ('دینار کویت', 'دینار کویت')
          : ('Kuwaiti dinar', 'Kuwaiti dinars'),
    'CHF' =>
      persian
          ? ('فرانک سوئیس', 'فرانک سوئیس')
          : ('Swiss franc', 'Swiss francs'),
    'CAD' =>
      persian
          ? ('دلار کانادا', 'دلار کانادا')
          : ('Canadian dollar', 'Canadian dollars'),
    'AUD' =>
      persian
          ? ('دلار استرالیا', 'دلار استرالیا')
          : ('Australian dollar', 'Australian dollars'),
    'TRY' => persian ? ('لیر', 'لیر') : ('lira', 'lira'),
    'CNY' => persian ? ('یوان', 'یوان') : ('yuan', 'yuan'),
    _ => (currency, currency),
  };
  return plural ? names.$2 : names.$1;
}
