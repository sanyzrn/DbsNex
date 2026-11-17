import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/card_number.dart';
import 'package:nex_client/modules/lent_borrowed/iban.dart';
import 'package:nex_client/modules/lent_borrowed/payment_cards.dart';

/// Card numbers and IBANs people share to be paid: checked offline, grouped
/// for reading, and never asking for anything secret.
void main() {
  group('card numbers', () {
    test('a 16-digit number is Luhn-checked', () {
      expect(luhnOk('6037991234567893'), isTrue);
      expect(luhnOk('6037991234567890'), isFalse);
      expect(luhnOk('603799123456789'), isFalse);
      expect(luhnOk('0000000000000000'), isTrue);
    });

    test('digits fold from Persian and Arabic, everything else drops', () {
      expect(cardDigits('۶۰۳۷ ۹۹۱۲-۳۴۵۶ ۷۸۹۳'), '6037991234567893');
      expect(cardDigits('٦٠٣٧٩٩١٢٣٤٥٦٧٨٩٣'), '6037991234567893');
      expect(cardDigits('6037 9912 3456 7893'), '6037991234567893');
    });

    test('cards are grouped the way they are read aloud', () {
      expect(groupCard('6037991234567893'), '6037 9912 3456 7893');
      expect(groupCard('603799'), '6037 99');
    });

    test('the first six digits name the bank, or honestly do not', () {
      expect(bankOf('6037991234567893')?.en, 'Bank Melli Iran');
      expect(bankOf('6104339999999999')?.fa, 'بانک ملت');
      expect(bankOf('9999991234567893'), isNull);
      // Corrected in review (2.8.4): 639346 is Sina, Refah is 589463.
      expect(bankOf('6393461234567890')?.en, 'Sina Bank');
      expect(bankOf('5894631234567890')?.en, 'Bank Refah Kargaran');
      expect(bankOf('5028061234567890')?.fa, 'بانک شهر');
      expect(bankOf('6037'), isNull);
      expect(cardTableChecked, '2026-11-17');
    });
  });

  group('IBAN', () {
    test('a real Iranian IBAN passes mod 97', () {
      expect(ibanOk('IR820540102680020817909002'), isTrue);
      expect(ibanOk('IR820540102680020817909001'), isFalse);
      expect(ibanOk('IR82054010268002081790900'), isFalse);
      expect(ibanOk(''), isFalse);
    });

    test('spaces, lower case and Persian digits are the same IBAN', () {
      expect(
        ibanNormalize('ir82 0540 1026 8002 0817 9090 02'),
        'IR820540102680020817909002',
      );
      expect(
        ibanNormalize('IR۸۲۰۵۴۰۱۰۲۶۸۰۰۲۰۸۱۷۹۰۹۰۰۲'),
        'IR820540102680020817909002',
      );
    });

    test('groups of four, with the country letters kept', () {
      expect(
        groupIban('IR820540102680020817909002'),
        'IR82 0540 1026 8002 0817 9090 02',
      );
    });
  });

  group('a saved card', () {
    test('keeps only what may be stored', () {
      final card = PaymentCard.fromBody('c1', {
        'v': 1,
        'person': ' Sara ',
        'holder': 'Sara A.',
        'card': '6037 9912 3456 7893',
        'iban': 'IR820540102680020817909002',
        'cvv2': '123',
        'expiry': '12/29',
      });
      expect(card.person, 'Sara');
      expect(card.card, '6037991234567893');
      expect(card.iban, 'IR820540102680020817909002');
      expect(card.toJson().keys, isNot(contains('cvv2')));
      expect(card.toJson().keys, isNot(contains('expiry')));
      expect(
        card.toJson().keys,
        containsAll(['person', 'holder', 'card', 'iban']),
      );
    });

    test('a broken number is not kept as if it were a card', () {
      final card = PaymentCard.fromBody('c1', {
        'person': 'Ali',
        'card': '6037991234567890',
        'iban': 'IR000000000000000000000000',
      });
      expect(card.card, isEmpty);
      expect(card.iban, isEmpty);
      expect(card.isEmpty, isTrue);
    });

    test('two names that read the same are one person', () {
      final card = PaymentCard.fromBody('c1', {'person': 'سارا'});
      expect(card.personKey, personKeyOf('سارا'));
      expect(card.personKey, personKeyOf(' سارا '));
    });
  });
}
