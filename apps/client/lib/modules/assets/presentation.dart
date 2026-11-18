import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'model.dart';
import 'money_format.dart';
import 'strings.dart';

/// The currencies people in Iran hold most, by name (2.8.4); any other is
/// shown by its code.
const _currencyNames = <String, (String, String)>{
  'USD': ('US dollar', 'دلار آمریکا'),
  'EUR': ('Euro', 'یورو'),
  'GBP': ('British pound', 'پوند انگلیس'),
  'AED': ('UAE dirham', 'درهم امارات'),
  'TRY': ('Turkish lira', 'لیر ترکیه'),
  'CNY': ('Chinese yuan', 'یوان چین'),
  'IQD': ('Iraqi dinar', 'دینار عراق'),
  'CAD': ('Canadian dollar', 'دلار کانادا'),
  'AUD': ('Australian dollar', 'دلار استرالیا'),
  'JPY': ('Japanese yen', 'ین ژاپن'),
  'KWD': ('Kuwaiti dinar', 'دینار کویت'),
  'CHF': ('Swiss franc', 'فرانک سوئیس'),
  'RUB': ('Russian rouble', 'روبل روسیه'),
  'AFN': ('Afghan afghani', 'افغانی'),
};

/// A currency's name in the page's language, or its code.
String currencyName(BuildContext c, String code) {
  final names = _currencyNames[code];
  if (names == null) return code;
  return NexModuleStrings.persian(c) ? names.$2 : names.$1;
}

String marketLabel(BuildContext c, AssetMarket m, {bool forQuote = false}) {
  if (m.custom) return m.name;
  return switch (m.type) {
    AssetType.currency => currencyName(c, m.code),
    AssetType.coin => assetStrings(c, m.code),
    AssetType.gold => assetStrings(c, forQuote ? 'metalRate' : 'gold'),
    AssetType.other => assetStrings(c, 'other'),
  };
}

IconData marketIcon(AssetType type) => switch (type) {
  AssetType.gold => Icons.diamond_outlined,
  AssetType.coin => Icons.toll_outlined,
  AssetType.currency => Icons.currency_exchange_outlined,
  AssetType.other => Icons.inventory_2_outlined,
};

String assetDate(BuildContext c, DateTime day) {
  final fa = NexModuleStrings.persian(c);
  return nexReadableDate(day, solar: fa, persian: fa);
}

String fixedNumber(BigInt amount, int digits, bool fa) {
  final factor = BigInt.from(moneyFactor(digits));
  final absolute = amount.abs();
  final whole = (absolute ~/ factor).toString();
  final groups = <String>[];
  for (var end = whole.length; end > 0; end -= 3) {
    groups.insert(0, whole.substring((end - 3).clamp(0, end), end));
  }
  final fraction = (absolute % factor)
      .toString()
      .padLeft(digits, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  final text =
      '${amount.isNegative ? '−' : ''}${groups.join(fa ? '٬' : ',')}'
      '${fraction.isEmpty ? '' : '${fa ? '٫' : '.'}$fraction'}';
  return nexDigits(text, persian: fa);
}

String moneyLabel(BuildContext c, BigInt rial, IrrUnit unit) {
  final fa = NexModuleStrings.persian(c);
  if (rial.abs() <= BigInt.from(maxMoney)) {
    return formatAmount(rial.toInt(), 'IRR', 0, fa, unit);
  }
  return '${fixedNumber(rial, unit.displayDigits, fa)} ${assetStrings(c, unit.key)}';
}
