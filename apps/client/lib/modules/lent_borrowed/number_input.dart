/// Accept Latin, Persian and Arabic-Indic digits without floating point.
String normalizeNumber(String raw) => raw
    .trim()
    .replaceAllMapped(RegExp(r'[۰-۹٠-٩]'), (m) {
      final code = m[0]!.codeUnitAt(0);
      return '${code >= 0x06f0 ? code - 0x06f0 : code - 0x0660}';
    })
    .replaceAll('−', '-');

int? parseWhole(String raw, {bool signed = false, int max = 365000}) {
  final text = normalizeNumber(raw);
  if (!(signed ? RegExp(r'^-?[0-9]+$') : RegExp(r'^[0-9]+$')).hasMatch(text)) {
    return null;
  }
  final value = int.tryParse(text);
  return value != null && value.abs() <= max ? value : null;
}

int safeWhole(Object? raw, {int fallback = 0, int max = 9007199254740991}) {
  if (raw is! num ||
      !raw.isFinite ||
      raw < 0 ||
      raw > max ||
      raw != raw.truncateToDouble()) {
    return fallback;
  }
  return raw.toInt();
}
