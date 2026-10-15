import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';

/// Records read defensively: a loan or return written by an older version
/// opens instead of crashing, and impossible dates read as unknown rather
/// than as deadlines in the year 26.
void main() {
  ModuleRecord record(
    String id,
    Map<String, Object?> body, {
    String kind = 'loan',
  }) => ModuleRecord(
    module: 'lent_borrowed',
    kind: kind,
    id: id,
    body: body,
    updatedAt: DateTime(2026, 10, 12),
  );

  group('Loan', () {
    test('reads a well-formed money record', () {
      final loan = Loan.fromRecord(
        record('l1', {
          'direction': 'borrowed',
          'person': 'Sara',
          'type': 'money',
          'amount': 750000,
          'what': '',
          'issued': '2026-10-01',
          'due': '2026-10-20',
          'note': 'for the tickets',
        }),
      );
      expect(loan.direction, LoanDirection.borrowed);
      expect(loan.person, 'Sara');
      expect(loan.kind, LoanKind.money);
      expect(loan.amount, 750000);
      expect(loan.issued, '2026-10-01');
      expect(loan.due, '2026-10-20');
      expect(loan.note, 'for the tickets');
    });

    test('reads a well-formed item record', () {
      final loan = Loan.fromRecord(
        record('l1', {
          'direction': 'lent',
          'person': 'Ali',
          'type': 'item',
          'amount': 2,
          'what': 'The blue backpack',
          'issued': '2026-10-02',
          'due': null,
          'note': '',
        }),
      );
      expect(loan.kind, LoanKind.item);
      expect(loan.amount, 2);
      expect(loan.what, 'The blue backpack');
      expect(loan.due, isNull);
    });

    test('missing fields read as their defaults', () {
      final loan = Loan.fromRecord(record('l1', {}));
      expect(loan.direction, LoanDirection.lent);
      expect(loan.person, '');
      expect(loan.kind, LoanKind.money);
      expect(loan.amount, 0);
      expect(
        loan.issued,
        civilDateKey(DateTime.now()),
        reason: 'an unknown issue date is today, not 1970',
      );
      expect(loan.due, isNull);
      expect(loan.note, '');
    });

    test('wrong-typed fields read as their defaults', () {
      final loan = Loan.fromRecord(
        record('l1', {
          'direction': 7,
          'person': 42,
          'type': 'favour',
          'amount': 'lots',
          'what': true,
          'issued': '2026-13-45',
          'due': 'soon',
          'note': 9,
        }),
      );
      expect(loan.direction, LoanDirection.lent);
      expect(loan.person, '');
      expect(loan.kind, LoanKind.money);
      expect(loan.amount, 0);
      expect(loan.due, isNull, reason: 'an impossible due date is no due date');
      expect(loan.note, '');
    });

    test('out-of-range amounts are clamped', () {
      final loan = Loan.fromRecord(record('l1', {'amount': -100}));
      expect(loan.amount, 0);
      final huge = Loan.fromRecord(record('l1', {'amount': 1e15}));
      expect(huge.amount, 1000000000000000);
    });

    test('toJson round-trips both kinds', () {
      final money = Loan(
        id: 'l1',
        direction: LoanDirection.borrowed,
        person: 'Sara',
        kind: LoanKind.money,
        amount: 750000,
        what: '',
        issued: '2026-10-01',
        due: '2026-10-20',
        note: 'for the tickets',
      );
      final again = Loan.fromBody('l1', money.toJson());
      expect(again.direction, LoanDirection.borrowed);
      expect(again.amount, 750000);
      expect(again.due, '2026-10-20');

      final item = Loan(
        id: 'l2',
        direction: LoanDirection.lent,
        person: 'Ali',
        kind: LoanKind.item,
        amount: 2,
        what: 'The blue backpack',
        issued: '2026-10-02',
        due: null,
        note: '',
      );
      final itemAgain = Loan.fromBody('l2', item.toJson());
      expect(itemAgain.kind, LoanKind.item);
      expect(itemAgain.what, 'The blue backpack');
      expect(itemAgain.amount, 2);
      expect(itemAgain.due, isNull);
    });
  });

  group('LoanReturn', () {
    test('reads a well-formed return', () {
      final record = LoanReturn.fromBody('r1', {
        'loan': 'l1',
        'date': '2026-10-05',
        'amount': 250000,
      });
      expect(record.loanId, 'l1');
      expect(record.date, '2026-10-05');
      expect(record.amount, 250000);
    });

    test('missing and impossible fields read as their defaults', () {
      final record = LoanReturn.fromBody('r1', {
        'loan': 5,
        'date': 'eventually',
        'amount': 'some',
      });
      expect(record.loanId, '');
      expect(record.date, '', reason: 'an unknown date stays unknown');
      expect(record.amount, 0);
    });

    test('toJson round-trips', () {
      final record = LoanReturn(
        id: 'r1',
        loanId: 'l1',
        date: '2026-10-05',
        amount: 250000,
      );
      final again = LoanReturn.fromBody('r1', record.toJson());
      expect(again.loanId, 'l1');
      expect(again.date, '2026-10-05');
      expect(again.amount, 250000);
    });
  });

  test('the direction keys are stable strings', () {
    expect(LoanDirection.lent.key, 'lent');
    expect(LoanDirection.borrowed.key, 'borrowed');
    expect(LoanDirection.fromKey('borrowed'), LoanDirection.borrowed);
    expect(LoanDirection.fromKey('anything-else'), LoanDirection.lent);
    expect(LoanKind.money.key, 'money');
    expect(LoanKind.item.key, 'item');
  });
}
