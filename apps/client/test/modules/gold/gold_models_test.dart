import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/modules/gold/gold_math.dart';
import 'package:nex_client/modules/gold/gold_models.dart';

/// The saved quotation: a full snapshot that round-trips through the
/// store's JSON, and survives records that are old, half-empty or wrong.
void main() {
  GoldQuote exampleQuote() => GoldQuote(
    id: 'q1',
    title: 'Wedding ring',
    shop: 'طلافروشی مهربان',
    savedAtIso: '2026-10-12T10:00:00',
    quoteDateIso: '2026-10-12',
    notes: 'Asked at the counter',
    input: const GoldInput(
      weightMg: 3000,
      grossWeightMg: 3100,
      finenessPpt: 750,
      rateCentiPerG: 1000000000,
      rateRefPpt: 750,
      makingMode: GoldMakingMode.percent,
      makingPercentBp: 1000,
      profitBp: 700,
      vatBp: 1000,
      commissionRial: 200000,
      extras: [('stones', 5000000)],
      shopQuoteRial: 358410000,
    ),
    metalValueRial: 300000000,
    makingChargeRial: 30000000,
    sellerProfitRial: 23100000,
    commissionRial: 200000,
    vatBaseRial: 53300000,
    vatRial: 5330000,
    extrasRial: 5000000,
    estimatedTotalRial: 363630000,
  );

  test('a saved quote round-trips through record JSON unchanged', () {
    final record = exampleQuote().toRecord();
    final back = GoldQuote.fromRecord('q1', record);
    expect(back.id, 'q1');
    expect(back.title, 'Wedding ring');
    expect(back.shop, 'طلافروشی مهربان');
    expect(back.quoteDateIso, '2026-10-12');
    expect(back.input.weightMg, 3000);
    expect(back.input.grossWeightMg, 3100);
    expect(back.input.finenessPpt, 750);
    expect(back.input.rateCentiPerG, 1000000000);
    expect(back.input.makingMode, GoldMakingMode.percent);
    expect(back.input.makingPercentBp, 1000);
    expect(back.input.profitBp, 700);
    expect(back.input.vatBp, 1000);
    expect(back.input.commissionRial, 200000);
    expect(back.input.extras, [('stones', 5000000)]);
    expect(back.input.shopQuoteRial, 358410000);
    expect(back.metalValueRial, 300000000);
    expect(back.vatBaseRial, 53300000);
    expect(back.estimatedTotalRial, 363630000);
    expect(back.schema, 2);
  });

  test('the record holds only what JSON holds', () {
    final record = exampleQuote().toRecord();
    for (final value in record.values) {
      expect(
        value is String || value is num || value is bool || value is List,
        isTrue,
      );
    }
    for (final extra in record['extras']! as List<Object?>) {
      expect(extra, isA<Map<String, Object?>>());
    }
  });

  test('an empty record reads back as defaults, not as a crash', () {
    final quote = GoldQuote.fromRecord('x', const {});
    expect(quote.title, '');
    expect(quote.input.weightMg, 0);
    expect(quote.input.finenessPpt, 750);
    expect(quote.input.profitBp, 700);
    expect(quote.input.vatBp, 1000);
    expect(quote.input.makingMode, GoldMakingMode.percent);
    expect(quote.input.extras, isEmpty);
    expect(quote.estimatedTotalRial, 0);
    expect(quote.schema, 1);
  });

  test('nonsense fields fall back to defaults one field at a time', () {
    final quote = GoldQuote.fromRecord('x', {
      'title': 12, // not a string
      'weightMg': 'heavy', // not a number
      'finenessPpt': 3.5, // fractional fineness metadata is invalid
      'makingMode': 'under-the-table', // unknown mode
      'extras': [
        {'label': 'stones', 'amount': 'many'}, // amount not a number
        {'label': '', 'amount': 5}, // no name
        'not even a map',
      ],
      'schema': 'one',
    });
    expect(quote.title, '12'); // stringified, never thrown away
    expect(quote.input.weightMg, 0);
    expect(quote.input.finenessPpt, 750);
    expect(quote.input.makingMode, GoldMakingMode.percent);
    // The unnameable extras are dropped rather than priced.
    expect(quote.input.extras, isEmpty);
    expect(quote.schema, 1);
  });

  test('a zero-amount extra is kept; a non-number amount is not', () {
    final quote = GoldQuote.fromRecord('x', {
      'extras': [
        {'label': 'box', 'amount': 0}, // a zero really saved — kept
        {'label': 'gift', 'amount': 'free'}, // not a number — dropped
        {'label': '', 'amount': 5}, // no name — dropped
      ],
    });
    // The zero survives the read, so editing and re-saving the record does
    // not quietly lose the row.
    expect(quote.input.extras, [('box', 0)]);
  });

  test('sameBasisAs is weight, fineness and rate basis together', () {
    final a = exampleQuote();
    expect(a.sameBasisAs(exampleQuote()), isTrue);

    final heavier = exampleQuote();
    final record = heavier.toRecord()..['weightMg'] = 4000;
    expect(a.sameBasisAs(GoldQuote.fromRecord('q2', record)), isFalse);

    final otherKarat = exampleQuote();
    final karatRecord = otherKarat.toRecord()..['finenessPpt'] = 875;
    expect(a.sameBasisAs(GoldQuote.fromRecord('q3', karatRecord)), isFalse);

    final otherRateBasis = exampleQuote();
    final rateRecord = otherRateBasis.toRecord()..['rateRefPpt'] = 875;
    expect(a.sameBasisAs(GoldQuote.fromRecord('q4', rateRecord)), isFalse);
  });

  test('withRecalculated keeps identity and words, replaces the numbers', () {
    final original = exampleQuote();
    const newInput = GoldInput(
      weightMg: 3000,
      finenessPpt: 750,
      rateCentiPerG: 1000000000,
      rateRefPpt: 750,
      makingPercentBp: 1000,
      profitBp: 700,
      vatBp: 900, // the VAT was edited down
    );
    final result = GoldMath.calculate(newInput);
    final edited = original.withRecalculated(newInput, result);
    expect(edited.id, original.id);
    expect(edited.title, original.title);
    expect(edited.shop, original.shop);
    expect(edited.quoteDateIso, original.quoteDateIso);
    expect(edited.vatRial, 5310000 - 531000); // 9% of the base now
    expect(edited.estimatedTotalRial, 357879000);
  });
}
