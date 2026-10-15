/// The saved quotation: one record, one kind, everything the estimate was
/// made of — because a saved estimate is a promise about what was entered
/// *that day*, not a live spreadsheet that follows today's rates.
///
/// Kind: `quote`. Schema version 2; version-1 snapshots remain readable. Every reader is defensive: a record
/// from a future or corrupt shape becomes a quote with defaults filled in
/// and the odd field dropped, never a crash and never a silent
/// re-calculation with today's numbers.
library;

import 'gold_math.dart';

class GoldQuote {
  const GoldQuote({
    required this.id,
    required this.title,
    required this.shop,
    required this.savedAtIso,
    required this.quoteDateIso,
    required this.notes,
    required this.input,
    required this.metalValueRial,
    required this.makingChargeRial,
    required this.sellerProfitRial,
    required this.commissionRial,
    required this.vatBaseRial,
    required this.vatRial,
    required this.extrasRial,
    required this.estimatedTotalRial,
    this.schema = 2,
  });

  /// The record's id — a UUIDv7 from the store, kept across edits.
  final String id;
  final String title;
  final String shop;

  /// When this record was last saved (ISO 8601, the store's clock).
  final String savedAtIso;

  /// The day the shop gave the estimate for — the «quote date» shown on
  /// the receipt and kept in the snapshot.
  final String quoteDateIso;

  final String notes;

  /// Everything that was entered, exactly as it was entered.
  final GoldInput input;

  /// The receipt as it was computed at save time. Kept so that changing
  /// defaults later (a new VAT rate, another profit suggestion) never
  /// rewrites what a person was told on an older estimate.
  final int metalValueRial;
  final int makingChargeRial;
  final int sellerProfitRial;
  final int commissionRial;
  final int vatBaseRial;
  final int vatRial;
  final int extrasRial;
  final int estimatedTotalRial;
  final int schema;

  /// From the store's JSON. Unknown fields are ignored; missing ones get
  /// the documented defaults; nonsense in a numeric field drops that field
  /// to its default rather than taking the record down.
  factory GoldQuote.fromRecord(String id, Map<String, Object?> body) {
    final extras = <(String, int)>[];
    for (final raw in _list(body, 'extras')) {
      if (raw is Map<String, Object?>) {
        final label = '${raw['label'] ?? ''}'.trim();
        final amount = _int(raw['amount']) ?? 0;
        if (label.isNotEmpty && amount > 0) extras.add((label, amount));
      }
    }
    final mode = switch ('${body['makingMode'] ?? ''}') {
      'perGram' => GoldMakingMode.perGram,
      'fixed' => GoldMakingMode.fixed,
      'mixed' => GoldMakingMode.mixed,
      _ => GoldMakingMode.percent,
    };
    final input = GoldInput(
      weightMg: _int(body['weightMg']) ?? 0,
      grossWeightMg: _int(body['grossWeightMg']) ?? 0,
      finenessPpt: _int(body['finenessPpt']) ?? 750,
      rateCentiPerG: _int(body['rateCentiPerG']) ?? 0,
      rateRefPpt: _int(body['rateRefPpt']) ?? 750,
      makingMode: mode,
      makingPercentBp: _int(body['makingPercentBp']) ?? 0,
      makingPerGramCenti: _int(body['makingPerGramCenti']) ?? 0,
      makingFixedRial: _int(body['makingFixedRial']) ?? 0,
      profitBp: _int(body['profitBp']) ?? 700,
      vatBp: _int(body['vatBp']) ?? 1000,
      commissionRial: _int(body['commissionRial']) ?? 0,
      profitBase:
          GoldProfitBase.values
              .where((value) => value.name == body['profitBase'])
              .firstOrNull ??
          GoldProfitBase.metalAndMaking,
      commissionTaxable: body['commissionTaxable'] != false,
      extras: extras,
      shopQuoteRial: _int(body['shopQuoteRial']) ?? 0,
    );
    return GoldQuote(
      id: id,
      title: '${body['title'] ?? ''}'.trim(),
      shop: '${body['shop'] ?? ''}'.trim(),
      savedAtIso: '${body['savedAt'] ?? ''}',
      quoteDateIso: '${body['quoteDate'] ?? ''}',
      notes: '${body['notes'] ?? ''}',
      input: input,
      metalValueRial: _int(body['snapMetalRial']) ?? 0,
      makingChargeRial: _int(body['snapMakingRial']) ?? 0,
      sellerProfitRial: _int(body['snapProfitRial']) ?? 0,
      commissionRial: _int(body['snapCommissionRial']) ?? 0,
      vatBaseRial: _int(body['snapVatBaseRial']) ?? 0,
      vatRial: _int(body['snapVatRial']) ?? 0,
      extrasRial: _int(body['snapExtrasRial']) ?? 0,
      estimatedTotalRial: _int(body['snapTotalRial']) ?? 0,
      schema: _int(body['schema']) ?? 1,
    );
  }

  /// The JSON that goes back into the store. Only what JSON holds: strings,
  /// numbers, booleans, lists and maps.
  Map<String, Object?> toRecord() => {
    'schema': schema,
    'title': title,
    'shop': shop,
    'savedAt': savedAtIso,
    'quoteDate': quoteDateIso,
    'notes': notes,
    'weightMg': input.weightMg,
    'grossWeightMg': input.grossWeightMg,
    'finenessPpt': input.finenessPpt,
    'rateCentiPerG': input.rateCentiPerG,
    'rateRefPpt': input.rateRefPpt,
    'makingMode': input.makingMode.name,
    'makingPercentBp': input.makingPercentBp,
    'makingPerGramCenti': input.makingPerGramCenti,
    'makingFixedRial': input.makingFixedRial,
    'profitBp': input.profitBp,
    'vatBp': input.vatBp,
    'commissionRial': input.commissionRial,
    'profitBase': input.profitBase.name,
    'commissionTaxable': input.commissionTaxable,
    'extras': [
      for (final (label, amount) in input.extras)
        {'label': label, 'amount': amount},
    ],
    'shopQuoteRial': input.shopQuoteRial,
    'snapMetalRial': metalValueRial,
    'snapMakingRial': makingChargeRial,
    'snapProfitRial': sellerProfitRial,
    'snapCommissionRial': commissionRial,
    'snapVatBaseRial': vatBaseRial,
    'snapVatRial': vatRial,
    'snapExtrasRial': extrasRial,
    'snapTotalRial': estimatedTotalRial,
  };

  /// Whether two saved quotes are on the same weight-and-karat basis, which
  /// is the only honest ground for comparing them.
  bool sameBasisAs(GoldQuote other) =>
      input.weightMg == other.input.weightMg &&
      input.finenessPpt == other.input.finenessPpt &&
      input.rateRefPpt == other.input.rateRefPpt;

  /// A snapshot with the receipt lines recomputed from the (possibly
  /// edited) input — used when a quote is edited and re-saved, never in
  /// the background.
  GoldQuote withRecalculated(GoldInput newInput, GoldResult result) =>
      GoldQuote(
        id: id,
        title: title,
        shop: shop,
        savedAtIso: savedAtIso,
        quoteDateIso: quoteDateIso,
        notes: notes,
        input: newInput,
        metalValueRial: result.metalValueRial,
        makingChargeRial: result.makingChargeRial,
        sellerProfitRial: result.sellerProfitRial,
        commissionRial: result.commissionRial,
        vatBaseRial: result.vatBaseRial,
        vatRial: result.vatRial,
        extrasRial: result.extrasRial,
        estimatedTotalRial: result.estimatedTotalRial,
        schema: schema,
      );
}

int? _int(Object? value) {
  if (value is int && value >= 0 && value <= goldMaxExact) return value;
  if (value is num &&
      value.isFinite &&
      value >= 0 &&
      value <= goldMaxExact &&
      value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

List<Object?> _list(Map<String, Object?> body, String key) {
  final value = body[key];
  return value is List<Object?> ? value : const [];
}
