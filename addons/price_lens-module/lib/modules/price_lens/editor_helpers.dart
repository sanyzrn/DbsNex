import 'package:flutter/material.dart';

import 'money.dart';
import 'options.dart';
import 'price_lens_common.dart';
import 'rational.dart';
import 'strings.dart';
import 'units.dart';
import 'local_values.dart';

/// The offer editor's parse-and-validate layer, kept out of the sheet
/// so the sheet stays small: the initial text for a reopened offer, the
/// money/count parsers with their rial/toman entry mode, and the error
/// texts the fields show. Everything here is pure — the sheet holds the
/// state, this decides what that state means.

String initialPriceText(PriceOption? existing) {
  if (existing == null ||
      priceCurrencyOf(existing.currency) == null ||
      (existing.source != null && !priceMetadataValid(existing.source!))) {
    return '';
  }
  return priceMajorText(
    existing.priceMinor,
    priceExponentOf(existing.currency),
  );
}

String initialQuantityText(PriceOption? existing) {
  if (existing == null) return '';
  return existing.quantity.toDecimalString(digits: 6);
}

/// A fixed discount prefills in major units, the way it was typed.
String initialDiscountText(PriceOption? existing, int exponent) {
  if (existing == null) return '';
  return switch (existing.discount) {
    DiscountKind.percent => '${existing.discountPercent ?? 0}',
    DiscountKind.fixed =>
      existing.discountMinor == null
          ? ''
          : priceMajorText(existing.discountMinor!, exponent),
    DiscountKind.none => '',
  };
}

String initialShippingText(PriceOption? existing, int exponent) =>
    existing?.shippingMinor == null
    ? ''
    : priceMajorText(existing!.shippingMinor!, exponent);

PriceCurrency initialCurrencyOf(PriceOption? existing) =>
    priceCurrencyOf(existing?.currency) ?? priceCurrencyOf('IRR')!;

/// Money text in the current entry mode (rial/toman aware).
PriceAmountResult parseMoneyIn(
  String text,
  PriceCurrency currency,
  IrrUnit irrUnit,
) => currency.code == 'IRR' && irrUnit == IrrUnit.toman
    ? parseTomanPrice(text)
    : parsePriceAmount(text, currency);

/// A whole-number count: null when nothing was typed, -1 when what was
/// typed is not a positive whole number under the module's bound.
int? parseCount(String text) {
  final trimmed = LocalValues.ascii(text.trim());
  if (trimmed.isEmpty) return null;
  final value = LocalValues.writtenCount(trimmed);
  if (value == null || value <= 0 || value > 100000) return -1;
  return value;
}

int quantityDecimalsOf(String text) {
  final normalized = LocalValues.ascii(text.trim()).replaceAll(',', '.');
  return normalized.contains('.') ? normalized.split('.').last.length : 0;
}

String? moneyErrorOf(BuildContext context, PriceAmountError? error) =>
    switch (error) {
      null => null,
      PriceAmountError.empty => null,
      PriceAmountError.zero => priceLensStrings(context, 'errZero'),
      PriceAmountError.notANumber => priceLensStrings(context, 'errNotNumber'),
      PriceAmountError.tooPrecise => priceLensStrings(context, 'errTooPrecise'),
      PriceAmountError.tooLarge => priceLensStrings(context, 'errTooLarge'),
    };

String? quantityErrorOf(
  BuildContext context, {
  required bool showErrors,
  required String text,
  required String unitKey,
}) {
  if (!showErrors) return null;
  if (text.trim().isEmpty) return null;
  final quantity = fractionFromDecimal(text);
  if (quantity == null) return priceLensStrings(context, 'errNotNumber');
  if (quantity <= const Fraction(0)) {
    return priceLensStrings(context, 'errQuantity');
  }
  if (quantityDecimalsOf(text) > priceUnitOf(unitKey)!.decimals) {
    return priceLensStrings(context, 'errQuantityTooPrecise');
  }
  return null;
}

String? countErrorOf(
  BuildContext context, {
  required bool showErrors,
  required String text,
}) {
  if (!showErrors) return null;
  if (text.trim().isEmpty) return null;
  if (parseCount(text) == -1) return priceLensStrings(context, 'errNotNumber');
  return null;
}

String? discountErrorOf(
  BuildContext context, {
  required bool showErrors,
  required DiscountKind kind,
  required String text,
  required String priceText,
  required PriceCurrency currency,
  required IrrUnit irrUnit,
}) {
  if (!showErrors) return null;
  if (kind == DiscountKind.percent) {
    final value = LocalValues.writtenCount(text.trim());
    if (value == null || value < 0 || value > 100) {
      return priceLensStrings(context, 'errNotNumber');
    }
    return null;
  }
  if (kind == DiscountKind.fixed) {
    if (text.trim().isEmpty) return null;
    final parsed = parseMoneyIn(text, currency, irrUnit);
    if (parsed.error != null) {
      return priceLensStrings(context, 'errNotNumber');
    }
    final price = parseMoneyIn(priceText, currency, irrUnit);
    if ((parsed.minor ?? 0) > (price.minor ?? 0)) {
      return priceLensStrings(context, 'errDiscountTooBig');
    }
  }
  return null;
}
