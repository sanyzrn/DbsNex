import 'money.dart';

/// schema 1/2 used 100 internal IRR units per rial. Preserve that scale in the
/// exact calculator; schema 3 names the persisted Iranian value explicitly.
int? storedPriceMinor(
  Map<String, Object?> body, {
  String legacy = 'price',
  String rial = 'priceRial',
}) {
  final code = body['currency_code'] ?? body['currency'];
  final canonical =
      body[code == 'IRR'
          ? rial
          : legacy == 'price'
          ? 'amount'
          : legacy];
  if (code == 'IRR' && body.containsKey(rial)) {
    if (canonical is! int || canonical < 0 || canonical > priceMax * 2 ~/ 100) {
      return null;
    }
    final minor = canonical * 100;
    return body.containsKey(legacy) && body[legacy] != minor ? null : minor;
  }
  if (code != 'IRR' && legacy == 'price' && body.containsKey('amount')) {
    if (canonical is! int ||
        (body.containsKey(legacy) && body[legacy] != canonical)) {
      return null;
    }
  }
  final old = body[legacy] ?? canonical;
  return old is int ? old : null;
}

Map<String, Object?> priceMoneyFields(
  int? minor,
  String code,
  Map<String, Object?>? source, {
  String legacy = 'price',
  String rial = 'priceRial',
}) {
  if (minor == null) return {};
  if (code == 'IRR' && minor % 100 == 0) {
    return {
      rial: minor ~/ 100,
      if (source?.containsKey(legacy) == true) legacy: minor,
    };
  }
  // Foreign smallest units; old fractional-rial quotes remain exact and
  // readable. They are never rounded into a fabricated whole-rial amount.
  return {
    if (code != 'IRR' && legacy == 'price') 'amount': minor else legacy: minor,
    if (code != 'IRR' && source?.containsKey(legacy) == true) legacy: minor,
  };
}

Map<String, Object?> keepUnknown(
  Map<String, Object?>? source,
  Set<String> controlled,
) => {
  if (source != null)
    for (final e in source.entries)
      if (!controlled.contains(e.key)) e.key: e.value,
};

bool priceSchemaKnown(Map<String, Object?> body) =>
    body['schema'] == null || {1, 2, 3}.contains(body['schema']);
