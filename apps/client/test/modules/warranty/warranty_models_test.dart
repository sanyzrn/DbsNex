import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/warranty/warranty_models.dart';
import 'package:nex_client/modules/warranty/warranty_parse.dart';

/// The stored shapes: what goes in, what comes back, and what happens to
/// an old or broken record — every reader is defensive, because a record
/// written by an earlier version has to keep opening.
void main() {
  group('warranty bodies', () {
    test('round-trips every field', () {
      final body = WarrantyModels.warrantyBody(
        product: ' Kettle ',
        category: 'Kitchen',
        brand: 'Boma',
        model: 'B-100',
        serial: 'AB123456',
        merchant: 'The shop',
        receiptRef: 'INV-99',
        coverageType: 'official',
        note: 'bought on sale',
        purchasedAt: DateTime.utc(2026, 10, 1),
        coverageEnd: DateTime.utc(2027, 10, 1),
        durationMonths: 12,
        amountRials: 30000000,
      );
      expect(WarrantyModels.readString(body, 'product'), 'Kettle');
      expect(WarrantyModels.readString(body, 'brand'), 'Boma');
      expect(WarrantyModels.readString(body, 'serial'), 'AB123456');
      expect(WarrantyModels.readString(body, 'receiptRef'), 'INV-99');
      expect(WarrantyModels.readCount(body, 'durationMonths'), 12);
      expect(WarrantyModels.readCount(body, 'amountRials'), 30000000);
      expect(
        WarrantyModels.readDate(body, 'purchasedAt'),
        DateTime.utc(2026, 10, 1),
      );
      expect(
        WarrantyModels.readDate(body, 'coverageEnd'),
        DateTime.utc(2027, 10, 1),
      );
      expect(WarrantyModels.readArchived(body), isFalse);
    });

    test('absent numbers stay absent, not zero', () {
      final body = WarrantyModels.warrantyBody(
        product: 'Kettle',
        category: '',
        brand: '',
        model: '',
        serial: '',
        merchant: '',
        receiptRef: '',
        coverageType: '',
        note: '',
        purchasedAt: DateTime.utc(2026, 10, 1),
        coverageEnd: DateTime.utc(2027, 10, 1),
      );
      expect(body.containsKey('durationMonths'), isFalse);
      expect(body.containsKey('amountRials'), isFalse);
    });

    test('malformed fields read as empty or null, never throw', () {
      const body = {
        'product': 7,
        'brand': true,
        'amountRials': -5,
        'durationMonths': 'twelve',
        'coverageEnd': 2027,
        'archived': 'yes',
      };
      expect(WarrantyModels.readString(body, 'product'), '');
      expect(WarrantyModels.readString(body, 'brand'), '');
      expect(WarrantyModels.readCount(body, 'amountRials'), isNull);
      expect(WarrantyModels.readCount(body, 'durationMonths'), isNull);
      expect(WarrantyModels.readDate(body, 'coverageEnd'), isNull);
      expect(WarrantyModels.readArchived(body), isFalse);
    });
  });

  group('claim bodies', () {
    test('a claim note with its date and kind', () {
      final body = WarrantyModels.claimBody(
        warrantyId: 'w1',
        kind: WarrantyModels.claimKind,
        note: 'Called the shop; part ordered.',
        at: DateTime.utc(2026, 10, 12, 9),
      );
      expect(body['warrantyId'], 'w1');
      expect(body['kind'], 'claim');
      expect(
        DateTime.parse(body['at']! as String),
        DateTime.utc(2026, 10, 12, 9),
      );
    });

    test('a service note is a service note', () {
      final body = WarrantyModels.claimBody(
        warrantyId: 'w1',
        kind: WarrantyModels.serviceKind,
        note: 'Annual check.',
        at: DateTime.utc(2026, 10, 12, 9),
      );
      expect(body['kind'], 'service');
    });
  });

  group('parsing what the editor holds', () {
    test('a date as written, with Persian digits', () {
      expect(WarrantyParse.date('2026/10/12'), DateTime(2026, 10, 12));
      expect(WarrantyParse.date('۲۰۲۶/۱۰/۱۲'), DateTime(2026, 10, 12));
      expect(WarrantyParse.date(''), isNull);
      expect(WarrantyParse.date('2026/10'), WarrantyParse.invalid);
      expect(WarrantyParse.date('not a date'), WarrantyParse.invalid);
      expect(WarrantyParse.date('1200/1/1'), WarrantyParse.invalid);
      expect(WarrantyParse.date('2200/1/1'), WarrantyParse.invalid);
    });

    test('a count as written', () {
      expect(WarrantyParse.count('12'), 12);
      expect(WarrantyParse.count('۱۲'), 12);
      expect(WarrantyParse.count(''), isNull);
      expect(WarrantyParse.count('twelve'), isNull);
    });

    test('amounts in either unit, exactly', () {
      expect(WarrantyParse.rials('3000000', inTomans: true), 30000000);
      expect(WarrantyParse.rials('30000000', inTomans: false), 30000000);
      expect(WarrantyParse.rials('', inTomans: true), isNull);
      expect(WarrantyParse.rials('-1', inTomans: false), isNull);
    });
  });
}
