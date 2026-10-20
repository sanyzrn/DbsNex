/// Gold Check's arithmetic — integer-scaled, never floating point.
///
/// Money is counted in **rials** (1 toman = 10 rials). Everything a person
/// can enter with a decimal point is stored as a scaled integer instead:
///
/// | Thing | Unit | Scale |
/// |---|---|---|
/// | net gold weight | milligrams | 1 mg = 1 «سوت» = 0.001 g |
/// | gold rate | centi-toman per gram | 0.01 toman/g == 1 deci-rial/g |
/// | per-gram making charge | centi-toman per gram | as above |
/// | percentages | basis points | 1% = 100 bp |
/// | fixed amounts | rials | entered in toman, ×10 |
///
/// One rounding rule everywhere: a line is rounded to the **nearest rial**
/// (halves away from zero, which is `[a + b/2] ~/ b` for the non-negative
/// values validation admits), and lines are summed **after** they are
/// rounded. Which lines exist and in what order is documented in
/// `README.md` and shown in the on-screen «How this is calculated» panel.
///
/// Intermediates use BigInt. Inputs have per-field caps, and calculated
/// monetary lines and totals must also fit the exact JSON integer range
/// (2^53 - 1). No overflow or silent clamp is accepted.
library;

part 'gold_calculation.dart';

/// How the making charge («اجرت») is worked out.
enum GoldMakingMode { percent, perGram, fixed, mixed }

enum GoldProfitBase { metalAndMaking, metalOnly, services }

/// The inputs of one estimate, already scaled to integers.
///
/// All fields are validated by [problems] before [GoldMath.calculate] will
/// touch them; the constructor itself stays dumb so tests can build any
/// shape of nonsense.
class GoldInput {
  const GoldInput({
    required this.weightMg,
    this.grossWeightMg = 0,
    required this.finenessPpt,
    required this.rateCentiPerG,
    required this.rateRefPpt,
    this.makingMode = GoldMakingMode.percent,
    this.makingPercentBp = 0,
    this.makingPerGramCenti = 0,
    this.makingFixedRial = 0,
    this.profitBp = 700,
    this.vatBp = 1000,
    this.commissionRial = 0,
    this.profitBase = GoldProfitBase.metalAndMaking,
    this.commissionTaxable = true,
    this.extras = const [],
    this.shopQuoteRial = 0,
  });

  /// Net weight of the **actual gold**, in milligrams. Stones, gems,
  /// leather and other non-gold parts must not be in here; the optional
  /// [grossWeightMg] exists so their mass can be *shown* as excluded.
  final int weightMg;

  /// Gross weight if the shop gave it (0 = not entered). Never priced.
  final int grossWeightMg;

  /// The item's fineness in parts per thousand (750 = 18k).
  final int finenessPpt;

  /// The entered rate in centi-toman per gram.
  final int rateCentiPerG;

  /// The fineness the entered rate is quoted for. When it differs from
  /// [finenessPpt] the rate is converted by the purity ratio — visibly,
  /// never silently.
  final int rateRefPpt;

  final GoldMakingMode makingMode;
  final int makingPercentBp;
  final int makingPerGramCenti;
  final int makingFixedRial;
  final int profitBp;
  final int vatBp;
  final int commissionRial;
  final GoldProfitBase profitBase;
  final bool commissionTaxable;

  /// Separately priced non-metal extras: (label, rials). Their tax is not
  /// modelled; the receipt says the invoice must match.
  final List<(String, int)> extras;

  /// The seller's quoted invoice total, if given (0 = not given).
  final int shopQuoteRial;

  /// The same input at another net weight — for answers that vary only the
  /// weight. The gross weight and the seller's quote are left out: neither
  /// belongs to a weight the person has not chosen.
  GoldInput withWeightMg(int weightMg) => GoldInput(
    weightMg: weightMg,
    finenessPpt: finenessPpt,
    rateCentiPerG: rateCentiPerG,
    rateRefPpt: rateRefPpt,
    makingMode: makingMode,
    makingPercentBp: makingPercentBp,
    makingPerGramCenti: makingPerGramCenti,
    makingFixedRial: makingFixedRial,
    profitBp: profitBp,
    vatBp: vatBp,
    commissionRial: commissionRial,
    profitBase: profitBase,
    commissionTaxable: commissionTaxable,
    extras: extras,
  );

  static const int maxWeightMg = 10000000; // 10 kg of jewelry is already absurd
  static const int maxGrossMg = 100000000;
  static const int minPpt = 100;
  static const int maxPpt = 999;
  static const int maxRateCenti = 10000000000; // 10^8 toman/g
  static const int maxPercentBp = 99999; // 999.99 %
  static const int maxPerGramCenti = 10000000000;
  static const int maxAmountRial = 1000000000000000; // 10^14 toman

  /// One line per problem, in the order the fields appear in. An empty
  /// list means the input may be calculated.
  List<GoldProblem> problems() {
    final out = <GoldProblem>[];
    void check(bool bad, GoldProblemField field) {
      if (bad) out.add(GoldProblem(field));
    }

    check(weightMg < 1 || weightMg > maxWeightMg, GoldProblemField.weight);
    check(
      grossWeightMg < 0 ||
          grossWeightMg > maxGrossMg ||
          (grossWeightMg > 0 && grossWeightMg < weightMg),
      GoldProblemField.grossWeight,
    );
    check(
      finenessPpt < minPpt || finenessPpt > maxPpt,
      GoldProblemField.fineness,
    );
    check(
      rateCentiPerG < 1 || rateCentiPerG > maxRateCenti,
      GoldProblemField.rate,
    );
    check(rateRefPpt < minPpt || rateRefPpt > maxPpt, GoldProblemField.rateRef);
    switch (makingMode) {
      case GoldMakingMode.percent:
        check(
          makingPercentBp < 0 || makingPercentBp > maxPercentBp,
          GoldProblemField.making,
        );
      case GoldMakingMode.perGram:
        check(
          makingPerGramCenti < 0 || makingPerGramCenti > maxPerGramCenti,
          GoldProblemField.making,
        );
      case GoldMakingMode.fixed:
        check(
          makingFixedRial < 0 || makingFixedRial > maxAmountRial,
          GoldProblemField.making,
        );
      case GoldMakingMode.mixed:
        check(
          makingPercentBp < 0 || makingPercentBp > maxPercentBp,
          GoldProblemField.making,
        );
        check(
          makingPerGramCenti < 0 || makingPerGramCenti > maxPerGramCenti,
          GoldProblemField.makingPerGram,
        );
    }
    check(profitBp < 0 || profitBp > maxPercentBp, GoldProblemField.profit);
    check(vatBp < 0 || vatBp > maxPercentBp, GoldProblemField.vat);
    check(
      commissionRial < 0 || commissionRial > maxAmountRial,
      GoldProblemField.commission,
    );
    for (final (label, amount) in extras) {
      check(
        amount < 0 || amount > maxAmountRial || label.trim().isEmpty,
        GoldProblemField.extras,
      );
    }
    check(
      shopQuoteRial < 0 || shopQuoteRial > maxAmountRial,
      GoldProblemField.shopQuote,
    );
    if (out.isEmpty) {
      try {
        GoldMath._calculate(this);
      } on RangeError {
        out.add(const GoldProblem(GoldProblemField.total));
      }
    }
    return out;
  }

  /// The entered rate expressed at the item's own fineness, by the purity
  /// ratio, rounded to the nearest centi-toman per gram.
  int get convertedRateCentiPerG => rateRefPpt == finenessPpt
      ? rateCentiPerG
      : _divRound(
          BigInt.from(rateCentiPerG) * BigInt.from(finenessPpt),
          BigInt.from(rateRefPpt),
        ).toInt();

  bool get rateWasConverted => rateRefPpt != finenessPpt;
}

/// Which field a [GoldProblem] belongs to — the UI marks that field.
enum GoldProblemField {
  weight,
  grossWeight,
  fineness,
  rate,
  rateRef,
  making,
  makingPerGram,
  profit,
  vat,
  commission,
  extras,
  shopQuote,
  total,
}

/// One invalid input, tied to its field. The fields' own validators put a
/// typed problem into words (`parse_*` in the strings); the form hides the
/// estimate and points at the marked fields while any of these remain.
class GoldProblem {
  const GoldProblem(this.field);
  final GoldProblemField field;
}

/// The receipt, line by line, in whole rials.
class GoldResult {
  const GoldResult({
    required this.metalValueRial,
    required this.makingChargeRial,
    required this.sellerProfitRial,
    required this.commissionRial,
    required this.vatBaseRial,
    required this.vatRial,
    required this.extrasRial,
    required this.estimatedTotalRial,
    required this.convertedRateCentiPerG,
    required this.rateWasConverted,
    required this.nonGoldMg,
    this.quoteDiffRial,
    this.quoteDiffHundredthsPct,
  });

  /// «ارزش ماده» — the gold itself. Not in the VAT base.
  final int metalValueRial;

  /// «اجرت ساخت».
  final int makingChargeRial;

  /// «سود فروشنده» — on metal + making.
  final int sellerProfitRial;

  /// «کارمزد» — only what was expressly entered.
  final int commissionRial;

  /// The taxable service subtotal: making + profit + commission.
  final int vatBaseRial;

  /// «مالیات بر ارزش افزوده» on [vatBaseRial].
  final int vatRial;

  /// Sum of the separately priced extras (tax on them not modelled).
  final int extrasRial;

  /// metal + making + profit + commission + VAT + extras.
  final int estimatedTotalRial;

  /// The rate after purity conversion, centi-toman per gram.
  final int convertedRateCentiPerG;

  /// Whether the purity ratio was applied to the entered rate.
  final bool rateWasConverted;

  /// gross − net, when a gross weight was given; 0 otherwise.
  final int nonGoldMg;

  /// shop quote − estimated, signed, when a quote was entered.
  final int? quoteDiffRial;

  /// The same difference as a percentage of the estimate, in hundredths of
  /// a percent (−37 = −0.37%), rounded to the nearest hundredth.
  final int? quoteDiffHundredthsPct;
}
