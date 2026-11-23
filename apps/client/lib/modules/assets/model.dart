import 'package:nex_client/modules/module_api.dart';

import 'currency_scales.dart';
import 'money_format.dart';

typedef Fields = Map<String, Object?>;

enum AssetType { gold, coin, currency, other }

enum Custody { home, bank, platform, other }

const coinCodes = ['emami', 'bahar', 'half', 'quarter', 'gram', 'custom'];

/// The currencies people in Iran quote and hold most, in the order the price
/// picker offers them. Any other held or quoted currency is still listed from
/// the person's own book.
const commonCurrencyCodes = [
  'USD',
  'EUR',
  'GBP',
  'AED',
  'TRY',
  'CNY',
  'IQD',
  'CAD',
  'AUD',
  'JPY',
  'KWD',
  'CHF',
  'RUB',
  'AFN',
];

String nameKey(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll(RegExp(r'[\s\u200c]+'), ' ');

DateTime civilDay(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime? readDay(Object? text) {
  if (text is! String) return null;
  final date = DateTime.tryParse(text);
  if (date == null ||
      date.year < 1900 ||
      date.year > 2100 ||
      date.toIso8601String() != text ||
      date != civilDay(date)) {
    return null;
  }
  return date;
}

bool positive(Object? value, [int limit = maxMoney]) =>
    value is int && value > 0 && value <= limit;
bool validName(Object? x, {bool empty = false}) =>
    x is String && x.length <= 120 && (empty || x.trim().isNotEmpty);

class AssetMarket {
  const AssetMarket(this.type, {this.code = '', this.name = ''});
  final AssetType type;
  final String code, name;
  static const gold = AssetMarket(AssetType.gold);
  static const usd = AssetMarket(AssetType.currency, code: 'USD');

  bool get custom =>
      type == AssetType.other || (type == AssetType.coin && code == 'custom');
  String get key => '${type.name}:$code:${custom ? nameKey(name) : ''}';
  int get digits => switch (type) {
    AssetType.gold => 3,
    AssetType.currency => currencyScales[code] ?? 2,
    _ => 0,
  };
  Fields get fields => {'type': type.name, 'code': code, 'name': name};

  static AssetMarket? read(Fields row) {
    final type = AssetType.values
        .where((t) => t.name == row['type'])
        .firstOrNull;
    final code = row['code'], name = row['name'];
    if (type == null || code is! String || !validName(name, empty: true)) {
      return null;
    }
    final result = AssetMarket(type, code: code, name: name as String);
    if (result.custom && !validName(name)) return null;
    return switch (type) {
      AssetType.gold || AssetType.other => code.isEmpty ? result : null,
      AssetType.currency =>
        currencyScales.containsKey(code) && code != 'IRR' ? result : null,
      AssetType.coin => coinCodes.contains(code) ? result : null,
    };
  }
}

/// Where an asset belongs in a list a person reads: gold, then the coins in
/// the order Iranians name them, then the currencies they quote most, then
/// everything the person named.
int marketRank(AssetMarket market) => switch (market.type) {
  AssetType.gold => 0,
  AssetType.coin => 10 + coinCodes.indexOf(market.code),
  AssetType.currency =>
    100 +
        (commonCurrencyCodes.contains(market.code)
            ? commonCurrencyCodes.indexOf(market.code)
            : commonCurrencyCodes.length),
  AssetType.other => 1000,
};

/// One stable order for the book, the price picker and the tests: a lot never
/// jumps to the top of the page just because it was edited.
int compareMarkets(AssetMarket a, AssetMarket b) {
  final byRank = marketRank(a).compareTo(marketRank(b));
  if (byRank != 0) return byRank;
  final byCode = a.code.compareTo(b.code);
  if (byCode != 0) return byCode;
  return nameKey(a.name).compareTo(nameKey(b.name));
}

/// Every asset whose price can be recorded before it is held: the 18k gram,
/// the standard coins and the currencies Iranians quote, plus whatever is
/// already in the person's own book (a held dirham, a named silver).
///
/// The price screen used to offer only gold, USD and what was already held or
/// quoted, so a person could not write down today's euro before buying it.
List<AssetMarket> priceCatalogue(Iterable<AssetMarket> known) {
  final markets = <String, AssetMarket>{};
  void add(AssetMarket market) => markets.putIfAbsent(market.key, () => market);

  add(AssetMarket.gold);
  for (final code in coinCodes) {
    if (code != 'custom') add(AssetMarket(AssetType.coin, code: code));
  }
  for (final code in commonCurrencyCodes) {
    add(AssetMarket(AssetType.currency, code: code));
  }
  for (final market in known) {
    add(market);
  }
  return markets.values.toList()..sort(compareMarkets);
}

class Holding {
  const Holding(
    this.record,
    this.market,
    this.quantity,
    this.fineness,
    this.bought,
    this.costPerUnitRial,
    this.custody,
    this.location,
  );
  final ModuleRecord record;
  final AssetMarket market;
  final int quantity, fineness, costPerUnitRial;
  final DateTime bought;
  final Custody custody;
  final String location;
  static Holding? read(ModuleRecord record) {
    final b = record.body;
    final m = AssetMarket.read(b), bought = readDay(b['bought']);
    final custody = Custody.values
        .where((c) => c.name == b['custody'])
        .firstOrNull;
    final qty = b[m?.type == AssetType.currency ? 'amount' : 'quantity'];
    final ppt = b['fineness'],
        paid = b['costPerUnitRial'],
        location = b['location'];
    if (record.module != 'assets' ||
        record.kind != 'holding' ||
        b['v'] != 1 ||
        m == null ||
        bought == null ||
        custody == null ||
        !positive(qty, 1000000000) ||
        !positive(ppt, 1000) ||
        paid is! int ||
        paid < 0 ||
        paid > maxMoney ||
        !validName(location, empty: custody != Custody.platform) ||
        (m.type == AssetType.currency && b['currency'] != m.code)) {
      return null;
    }
    return Holding(
      record,
      m,
      qty as int,
      ppt as int,
      bought,
      paid,
      custody,
      location as String,
    );
  }
}

class Quote {
  const Quote(this.record, this.market, this.date, this.unitRial);
  final ModuleRecord record;
  final AssetMarket market;
  final DateTime date;
  final int unitRial;
  static Quote? read(ModuleRecord record) {
    final b = record.body;
    final market = AssetMarket.read(b), date = readDay(b['date']);
    if (record.module != 'assets' ||
        record.kind != 'quote' ||
        b['v'] != 1 ||
        market == null ||
        date == null ||
        !positive(b['unitRial'])) {
      return null;
    }
    return Quote(record, market, date, b['unitRial'] as int);
  }
}

class AssetGoal {
  const AssetGoal(this.record, this.title, this.targetMg);
  final ModuleRecord record;
  final String title;
  final int targetMg;
  static AssetGoal? read(ModuleRecord record) {
    final b = record.body;
    if (record.module != 'assets' ||
        record.kind != 'goal' ||
        b['v'] != 1 ||
        !validName(b['title']) ||
        !positive(b['targetMg'], 1000000000)) {
      return null;
    }
    return AssetGoal(record, b['title'] as String, b['targetMg'] as int);
  }
}
