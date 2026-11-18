/// How a person says an Iranian amount: in tomans or in rials.
///
/// The official unit is the rial, and a toman is ten rials — but people in
/// Iran speak, price and budget in toman, so the module shows toman by
/// default and keeps rial a switch away (see the README's Research section).
///
/// Whatever is chosen, a record always stores **whole rials**: the unit is
/// how the amount is said, never how it is kept. That is what lets an old
/// record keep its meaning when the switch moves, and it is why the module
/// never applies a currency reform on its own — an amount stored before any
/// redenomination is still the amount that was lent.
enum IrrUnit {
  rial,
  toman;

  String get key => this == toman ? 'toman' : 'rial';

  /// A missing or malformed choice reads as toman, the module's default:
  /// the same answer a fresh installation gives.
  static IrrUnit fromKey(Object? raw) => raw == 'rial' ? rial : toman;

  /// How many rials one of this unit is worth. A toman is ten rials.
  int get factor => this == toman ? 10 : 1;

  /// How many decimals the amount is said with. A tenth of a toman exists
  /// (one rial); there is no smaller rial, so no more precision is offered.
  int get displayDigits => this == toman ? 1 : 0;
}
