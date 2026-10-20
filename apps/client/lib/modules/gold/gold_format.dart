/// Turning scaled integers into words on a screen, and typed text back
/// into scaled integers.
///
/// The app's own `nexDigits` helper is not exported through the module API,
/// so this is the module's local equivalent: grouped thousands, the
/// language's digits, and — for Persian — the Persian decimal separator
/// «٫» and percent sign «٪».
library;

// (No imports: this file is the module's own little number layer.)

const _enDigits = '0123456789';
const _faDigits = '۰۱۲۳۴۵۶۷۸۹';

/// `358410000` → `358,410,000` (en) / `۳۵۸٬۴۱۰٬۰۰۰` (fa).
String groupDigits(int value, {required bool persian}) {
  final negative = value < 0;
  final digits = (negative ? -value : value).toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    if (i > 0 && fromEnd % 3 == 0) grouped.write(persian ? '٬' : ',');
    grouped.write(digits[i]);
  }
  final out = grouped.toString();
  final withSign = negative ? (persian ? '−$out' : '-$out') : out;
  return persian ? _toPersianDigits(withSign) : withSign;
}

/// A decimal amount typed with an optional sign-free fractional part,
/// shown with the same grouping: `1234.5` → `1,234.5` / `۱٬۲۳۴٫۵`.
String groupDecimal(
  int whole,
  int fraction,
  int fractionDigits, {
  required bool persian,
}) {
  if (fractionDigits <= 0 || fraction == 0) {
    return groupDigits(whole, persian: persian);
  }
  final fractionText = fraction.toString().padLeft(fractionDigits, '0');
  final wholeText = groupDigits(whole, persian: persian);
  final joined = '$wholeText.$fractionText';
  if (!persian) return joined;
  return _toPersianDigits(joined.replaceFirst('.', '٫'));
}

/// 725 (basis points) → `7.25%` (en) / `۷٫۲۵٪` (fa).
String formatPercent(int basisPoints, {required bool persian}) {
  final negative = basisPoints < 0;
  final value = negative ? -basisPoints : basisPoints;
  final whole = value ~/ 100;
  final fraction = value % 100;
  final text = fraction == 0
      ? groupDigits(whole, persian: persian)
      : groupDecimal(whole, fraction, 2, persian: persian);
  final body = persian ? '$text٪' : '$text%';
  return negative ? (persian ? '−$body' : '-$body') : body;
}

/// 3000 mg → `3 g` (en) / `۳ گرم` (fa), the grams label coming from the
/// module's words so the unit is translated.
String formatWeightMg(int milligrams, {required bool persian}) {
  final grams = milligrams ~/ 1000;
  final soot = milligrams % 1000;
  return soot == 0
      ? groupDigits(grams, persian: persian)
      : groupDecimal(grams, soot, 3, persian: persian);
}

/// A rial amount shown in the unit the person picked. Toman conversion is
/// exact — a toman *is* ten rials — so a half-toman shows as one decimal
/// rather than being rounded away.
String formatRial(int rial, {required bool persian, required bool rials}) {
  if (rials) return groupDigits(rial, persian: persian);
  final negative = rial < 0;
  final value = negative ? -rial : rial;
  final whole = value ~/ 10;
  final tenths = value % 10;
  final text = tenths == 0
      ? groupDigits(whole, persian: persian)
      : groupDecimal(whole, tenths, 1, persian: persian);
  if (!negative) return text;
  return persian ? '−$text' : '-$text';
}

/// A rate held in centi-toman per gram, shown as toman per gram.
String formatCentiRate(int centi, {required bool persian}) {
  final whole = centi ~/ 100;
  final fraction = centi % 100;
  return groupDecimal(whole, fraction, 2, persian: persian);
}

/// Whether [text] is a real civil date in `YYYY-MM-DD` form — the shape
/// the module stores. The shared calendar button picks a day in the
/// person's own calendar and writes this same civil day into the field
/// (see `gold_save_sheet.dart` and `gold_dates.dart`). `2028-02-30` fails:
/// the day does not exist.
bool isIsoDate(String text) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})$',
  ).firstMatch(normalizeGoldDate(text));
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

/// «Saved when» in words: today, yesterday, a count of days, or the date
/// itself once the count stops being the useful part. Day arithmetic is
/// calendar days on date-only values, never 24-hour spans. The absolute
/// day is handed to [onDate] as a local civil `DateTime`, so the caller
/// can show it through the shared module date label in the person's own
/// calendar; it is never a UTC instant, which would print the day before
/// in a western zone.
String relativeDayWords(
  DateTime saved,
  DateTime now, {
  required String Function() today,
  required String Function() yesterday,
  required String Function(int) daysAgo,
  required String Function(DateTime) onDate,
}) {
  saved = saved.toLocal();
  now = now.toLocal();
  final savedDay = DateTime.utc(saved.year, saved.month, saved.day);
  final todayDay = DateTime.utc(now.year, now.month, now.day);
  final days = todayDay.difference(savedDay).inDays;
  final shownDay = DateTime(saved.year, saved.month, saved.day);
  if (days == 0) return today();
  if (days < 0) return onDate(shownDay);
  if (days == 1) return yesterday();
  return days < 30 ? daysAgo(days) : onDate(shownDay);
}

/// `YYYY-MM-DD` for a date-only value.
String isoDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The finenesses offered in the pickers, with their karat names.
const List<int> goldFinenessPresets = [999, 916, 875, 750];

String _toPersianDigits(String text) {
  var out = '';
  for (final rune in text.runes) {
    final index = _enDigits.indexOf(String.fromCharCode(rune));
    out += index < 0 ? String.fromCharCode(rune) : _faDigits[index];
  }
  return out;
}

// ------------------------------------------------------------- parsing

/// What can go wrong while reading a typed number — the field shows the
/// matching word from the module's strings.
enum GoldParseProblem { empty, invalid, tooManyDecimals, negative, tooBig }

/// Parses a typed decimal into a scaled integer.
///
/// `123.45` with scale 2 → `12345`. Accepts only plain digits and one dot;
/// the Persian digits a Persian keyboard produces are read as their
/// values, and the Persian decimal separator «٫» as a dot. Surrounding
/// whitespace is forgiven, everything else is not.
int? parseScaled(String text, int scale) {
  if (scale < 0 || scale > 6) return null;
  final normalized = _normalize(text);
  if (!RegExp(
    r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$',
  ).hasMatch(normalized)) {
    return null;
  }
  final negative = normalized.startsWith('-');
  final body = normalized.replaceFirst(RegExp(r'^[+-]'), '');
  final parts = body.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > scale) return null;
  final whole = BigInt.tryParse(parts[0].isEmpty ? '0' : parts[0]);
  if (whole == null) return null;
  final value =
      whole * BigInt.from(_pow10(scale)) +
      BigInt.parse(
        fraction.padRight(scale, '0').isEmpty
            ? '0'
            : fraction.padRight(scale, '0'),
      );
  if (value > BigInt.from(9007199254740991)) return null;
  return (negative ? -value : value).toInt();
}

/// Editable text has no grouping, unit or percent sign.
String inputScaled(int value, int scale) {
  final factor = _pow10(scale);
  final magnitude = value.abs();
  final fraction = (magnitude % factor)
      .toString()
      .padLeft(scale, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${value < 0 ? '-' : ''}${magnitude ~/ factor}${fraction.isEmpty ? '' : '.$fraction'}';
}

String normalizeGoldDate(String text) => _normalize(text);
String goldDigits(String text, bool persian) =>
    persian ? _toPersianDigits(text) : text;

/// [parseScaled] with the reasons kept: null result becomes a problem the
/// field can put into words.
(int?, GoldParseProblem?) parseScaledDetailed(String text, int scale) {
  final normalized = _normalize(text);
  if (normalized.isEmpty) return (null, GoldParseProblem.empty);
  if (normalized.startsWith('-')) {
    // A negative sign anywhere is rejected before anything else is read.
    final (value, _) = parseScaledDetailed(normalized.substring(1), scale);
    return (
      null,
      value == null ? GoldParseProblem.invalid : GoldParseProblem.negative,
    );
  }
  final body = normalized;
  final dotCount = '.'.allMatches(body).length;
  if (dotCount > 1) return (null, GoldParseProblem.invalid);
  final dot = body.indexOf('.');
  final wholeText = dot < 0 ? body : body.substring(0, dot);
  final fractionText = dot < 0 ? '' : body.substring(dot + 1);
  if (wholeText.isEmpty && fractionText.isEmpty) {
    return (null, GoldParseProblem.invalid);
  }
  if (!_allDigits(wholeText) || !_allDigits(fractionText)) {
    return (null, GoldParseProblem.invalid);
  }
  if (fractionText.length > scale) {
    return (null, GoldParseProblem.tooManyDecimals);
  }
  final value = parseScaled(body, scale);
  if (value == null) return (null, GoldParseProblem.tooBig);
  return (value, null);
}

/// The typed text in one canonical form: trimmed, Persian digits as ASCII
/// and the Persian decimal separator «٫» as `.`. A leading `+` is dropped.
/// A comma is **not** forgiven: half the world types it as a decimal
/// separator and the other half as a thousands separator, and guessing
/// wrong silently misprices a piece of jewelry. It is rejected instead.
String _normalize(String text) {
  var out = text.trim();
  if (out.startsWith('+')) out = out.substring(1);
  final buffer = StringBuffer();
  for (final rune in out.runes) {
    final char = String.fromCharCode(rune);
    final faIndex = _faDigits.indexOf(char);
    if (faIndex >= 0) {
      buffer.write(_enDigits[faIndex]);
    } else if ('٠١٢٣٤٥٦٧٨٩'.contains(char)) {
      buffer.write(_enDigits['٠١٢٣٤٥٦٧٨٩'.indexOf(char)]);
    } else if (char == '−') {
      buffer.write('-');
    } else if (char == '٫') {
      buffer.write('.');
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

bool _allDigits(String text) {
  for (final rune in text.runes) {
    if (rune < 0x30 || rune > 0x39) return false;
  }
  return true;
}

int _pow10(int n) {
  var out = 1;
  for (var i = 0; i < n; i++) {
    out *= 10;
  }
  return out;
}
