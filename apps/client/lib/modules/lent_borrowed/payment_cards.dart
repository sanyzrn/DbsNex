import 'package:nex_client/modules/module_api.dart';

import 'card_number.dart';
import 'iban.dart';
import 'loan_people.dart';

/// One person's way to be paid: a card number, an IBAN, or both, with the
/// account holder's name. Only numbers people give out to be paid — never a
/// CVV2, an expiry date or a PIN.
class PaymentCard {
  const PaymentCard({
    required this.id,
    required this.person,
    required this.holder,
    required this.card,
    required this.iban,
  });

  factory PaymentCard.fromRecord(ModuleRecord record) =>
      PaymentCard.fromBody(record.id, record.body);

  factory PaymentCard.fromBody(String id, Map<String, Object?> body) {
    final card = cardDigits('${body['card'] ?? ''}');
    return PaymentCard(
      id: id,
      person: body['person'] is String ? (body['person'] as String).trim() : '',
      holder: body['holder'] is String ? (body['holder'] as String).trim() : '',
      card: luhnOk(card) ? card : '',
      iban: ibanOk('${body['iban'] ?? ''}')
          ? ibanNormalize('${body['iban'] ?? ''}')
          : '',
    );
  }

  final String id;
  final String person;
  final String holder;

  /// 16 Latin digits, or empty when this person only gave an IBAN.
  final String card;

  /// `IR` + 24 digits, or empty when only a card was given.
  final String iban;

  String get personKey => personKeyOf(person);

  bool get isEmpty => card.isEmpty && iban.isEmpty;

  Map<String, Object?> toJson() => {
    'v': 1,
    'person': person,
    'holder': holder,
    'card': card,
    'iban': iban,
  };
}

String personKeyOf(String name) => personKey(name);

/// Every saved card, one per person: two records for the same person would
/// make "which one do I copy?" a question again. A newer save replaces the
/// older record's body.
Future<PaymentCard?> cardForPerson(NexModuleStore store, String person) async {
  final key = personKeyOf(person);
  if (key.isEmpty) return null;
  final records = await store.list('card');
  for (final record in records) {
    final card = PaymentCard.fromRecord(record);
    if (card.personKey == key) return card;
  }
  return null;
}

/// All cards, people with a balance first? Kept alphabetical by name, the
/// order a person scans a short list in.
Future<List<PaymentCard>> allCards(NexModuleStore store) async {
  final cards = (await store.list('card')).map(PaymentCard.fromRecord).toList()
    ..sort((a, b) {
      final byName = a.personKey.compareTo(b.personKey);
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
  return cards;
}

/// Saves [card] under its own record id (person key when new), so repeated
/// saves for one person never multiply records.
///
/// A new card for someone who already has one adopts that record: typing
/// the same person twice — from the book and from their page — updates the
/// details they gave instead of leaving two rows to choose between.
Future<PaymentCard> saveCard(
  NexModuleStore store,
  PaymentCard card, {
  String? existingId,
}) async {
  final adopted = existingId == null
      ? await cardForPerson(store, card.person)
      : null;
  final id = existingId ?? adopted?.id ?? card.id;
  // Fields this version does not know are kept (docs/18), and a record
  // that is adopted keeps what the new entry left blank (2.8.19): a second
  // save with only an IBAN no longer wiped the card number given before.
  final old = await store.get('card', id) ?? const <String, Object?>{};
  bool given(Object? value) =>
      value is String ? value.trim().isNotEmpty : value != null;
  final body = <String, Object?>{
    ...old,
    for (final entry in card.toJson().entries)
      if (adopted == null || given(entry.value)) entry.key: entry.value,
  };
  await store.put('card', id, body);
  return PaymentCard.fromBody(id, body);
}

/// The card/IBAN lines of a message: quiet, complete, and only the fields
/// the person actually saved.
List<String> paymentLines(
  PaymentCard? card, {
  required String cardLabel,
  required String ibanLabel,
  required String holderLabel,
}) {
  if (card == null || card.isEmpty) return const [];
  return [
    if (card.card.isNotEmpty)
      cardLabel.replaceAll('{card}', groupCard(card.card)),
    if (card.iban.isNotEmpty)
      ibanLabel.replaceAll('{iban}', groupIban(card.iban)),
    if (card.holder.isNotEmpty) holderLabel.replaceAll('{holder}', card.holder),
  ];
}
