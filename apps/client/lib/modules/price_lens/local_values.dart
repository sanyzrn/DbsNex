/// Strict parsing owned by this module.
class LocalValues {
  static const maxExact = 9007199254740991;
  static String ascii(String text) => text
      .replaceAllMapped(RegExp(r'[۰-۹٠-٩]'), (m) {
        final c = m[0]!.codeUnitAt(0);
        return '${c >= 0x6f0 ? c - 0x6f0 : c - 0x660}';
      })
      .replaceAll('−', '-')
      .replaceAll('٫', '.');
  static int? count(Object? raw) {
    if (raw is num) {
      if (!raw.isFinite ||
          raw < 0 ||
          raw > maxExact ||
          raw != raw.roundToDouble()) {
        return null;
      }
      return raw.toInt();
    }
    return null;
  }

  static int? writtenCount(String text) {
    final raw = ascii(text.trim());
    if (!RegExp(r'^\d+$').hasMatch(raw)) {
      return null;
    }
    return count(int.tryParse(raw));
  }

  static bool realDay(int y, int m, int d) {
    if (y < 1 || y > 9999 || m < 1 || m > 12 || d < 1 || d > 31) {
      return false;
    }
    final day = DateTime.utc(y, m, d);
    return day.year == y && day.month == m && day.day == d;
  }

  /// A typed shopping date, civil: `yyyy/MM/dd` (the shared date entry's
  /// format), one separator style throughout, 1900–2100 like the picker.
  static DateTime? day(String text) {
    final match = RegExp(
      r'^(\d{4})([/.-])(\d{1,2})\2(\d{1,2})$',
    ).firstMatch(ascii(text.trim()));
    if (match == null) {
      return null;
    }
    final y = int.parse(match[1]!);
    final m = int.parse(match[3]!);
    final d = int.parse(match[4]!);
    return y >= 1900 && y <= 2100 && realDay(y, m, d)
        ? DateTime(y, m, d)
        : null;
  }

  static DateTime? stamp(Object? raw) {
    if (raw is! String) {
      return null;
    }
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?)?$',
    ).firstMatch(raw);
    if (m == null ||
        !realDay(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!))) {
      return null;
    }
    if ((int.tryParse(m[4] ?? '0') ?? 24) > 23 ||
        (int.tryParse(m[5] ?? '0') ?? 60) > 59 ||
        (int.tryParse(m[6] ?? '0') ?? 60) > 59) {
      return null;
    }
    final offset = RegExp(r'[+-](\d{2}):?(\d{2})$').firstMatch(raw);
    if (offset != null &&
        (int.parse(offset[1]!) > 23 || int.parse(offset[2]!) > 59)) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
