import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  group('nexSearchFold', () {
    test('Arabic yeh and kaf read as the Persian letters', () {
      expect(nexSearchFold('كتاب'), 'کتاب');
      expect(nexSearchFold('علي'), 'علی');
      expect(nexSearchFold('مصطفى'), 'مصطفی');
    });

    test('harakat, tatweel and joiners are not letters', () {
      expect(nexSearchFold('مُهَمّ'), 'مهم');
      expect(nexSearchFold('کتـــاب'), 'کتاب');
      expect(nexSearchFold('کتاب‌ها'), 'کتابها');
      expect(nexSearchFold('‏سلام‎'), 'سلام');
    });

    test('every digit is a Latin digit', () {
      expect(nexSearchFold('۱۴۰۳'), '1403');
      expect(nexSearchFold('٢٠٢٥'), '2025');
      expect(nexSearchFold('room 12'), 'room 12');
    });

    test('alef madda and yeh with hamza are letters of their own', () {
      expect(nexSearchFold('آب'), 'آب');
      expect(nexSearchFold('مسئله'), 'مسئله');
      expect(nexSearchFold('أمر'), 'امر');
    });

    test('Latin text and emoji pass through untouched', () {
      expect(nexSearchFold('Hello 👋🏽 World'), 'Hello 👋🏽 World');
    });
  });

  group('nexSearchIndexText', () {
    test('a ZWNJ word is kept both split and joined', () {
      final indexed = nexSearchIndexText('كتاب‌های خوب');
      expect(indexed, contains('کتاب های خوب'));
      expect(indexed, contains('کتابهای'));
      expect(indexed, isNot(contains('‌')));
    });

    test('text without a ZWNJ is only folded', () {
      expect(nexSearchIndexText('مُهَمّ ٣'), 'مهم 3');
    });
  });
}
