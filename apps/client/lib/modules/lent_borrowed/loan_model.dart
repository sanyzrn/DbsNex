import 'package:nex_client/modules/module_api.dart';
import 'money_format.dart';
import 'number_input.dart';

/// Whether a record's debt runs toward the person or away from them.
enum LoanDirection {
  /// I lent: someone owes *me*.
  lent,

  /// I borrowed: I owe *someone*.
  borrowed;

  String get key => this == lent ? 'lent' : 'borrowed';

  static LoanDirection fromKey(String? key) =>
      key == 'borrowed' ? borrowed : lent;
}

/// Whether what changed hands was money or a thing.
enum LoanKind {
  money,
  item;

  String get key => this == money ? 'money' : 'item';

  static LoanKind fromKey(String? key) => key == 'item' ? item : money;
}

/// One lending or borrowing: who, what, when it was due back — and, for
/// items, how many. Stored as kind `loan`; every repayment/return is its
/// own `return` record pointing back here, so editing a loan can never
/// wipe its history.
class Loan {
  const Loan({
    required this.id,
    required this.direction,
    required this.person,
    required this.kind,
    required this.amount,
    required this.what,
    required this.issued,
    required this.due,
    required this.note,
    this.currency = 'IRR',
    this.currencyDecimals,
  });

  factory Loan.fromRecord(ModuleRecord record) =>
      Loan.fromBody(record.id, record.body);

  factory Loan.fromBody(String id, Map<String, Object?> body) {
    int whole(Object? v) => safeWhole(v);
    final kind = LoanKind.fromKey('${body['type'] ?? ''}');
    final due = _civilKey('${body['due'] ?? ''}');
    // A missing or impossible issue date reads as today: the record still
    // opens, and its age is honest about being unknown-length.
    final issued =
        _civilKey('${body['issued'] ?? ''}') ?? civilDateKey(DateTime.now());
    return Loan(
      id: id,
      currency: currencyCode(body['currency']),
      currencyDecimals: moneyDigits(
        currencyCode(body['currency']),
        body['currencyDecimals'],
      ),
      direction: LoanDirection.fromKey('${body['direction'] ?? ''}'),
      person: body['person'] is String ? body['person'] as String : '',
      kind: kind,
      // Money: rials. Items: the quantity. Integer either way.
      amount: whole(body['amount']).clamp(0, _maxAmount),
      what: body['what'] is String ? body['what'] as String : '',
      issued: issued,
      due: due,
      note: body['note'] is String ? body['note'] as String : '',
    );
  }

  static const int _maxAmount =
      maxMoney; // exact in both native and web runtimes

  final String id;
  final LoanDirection direction;

  /// The other person's name, as the person wrote it.
  final String person;

  final LoanKind kind;

  /// Money: the amount in integer rials. Items: the quantity.
  final int amount;

  /// What the item was, for item records. Empty for money.
  final String what;

  /// The local civil date it was issued, `YYYY-MM-DD`.
  final String issued;

  /// The local civil date it is due back, or null when there is no due
  /// date.
  final String? due;

  final String note;
  final String currency;
  final int? currencyDecimals;
  int get digits => moneyDigits(currency, currencyDecimals);

  Map<String, Object?> toJson() => {
    'v': 2,
    'currency': currency,
    'currencyDecimals': digits,
    'direction': direction.key,
    'person': person,
    'type': kind.key,
    'amount': amount,
    'what': kind == LoanKind.item ? what : '',
    'issued': issued,
    'due': due,
    'note': note,
  };

  /// An impossible date reads as no due date rather than as a deadline in
  /// the year 26.
  static String? _civilKey(String raw) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    final key = '${parsed.year}-${two(parsed.month)}-${two(parsed.day)}';
    return key == raw ? key : null;
  }
}

/// One repayment (money) or return (items): a slice of a loan, dated.
///
/// Stored as kind `return`, with an id of its own so partial returns
/// accumulate into a readable history and any one of them can be taken
/// back.
class LoanReturn {
  const LoanReturn({
    required this.id,
    required this.loanId,
    required this.date,
    required this.amount,
  });

  factory LoanReturn.fromRecord(ModuleRecord record) =>
      LoanReturn.fromBody(record.id, record.body);

  factory LoanReturn.fromBody(String id, Map<String, Object?> body) {
    int whole(Object? v) => safeWhole(v);
    final date = Loan._civilKey('${body['date'] ?? ''}');
    return LoanReturn(
      id: id,
      loanId: body['loan'] is String ? body['loan'] as String : '',
      date: date ?? '',
      amount: whole(body['amount']).clamp(0, Loan._maxAmount),
    );
  }

  final String id;

  /// The loan this return belongs to.
  final String loanId;

  /// When it came back, as a local civil date key. Empty when an old
  /// record lost it — read as "date unknown", never as today.
  final String date;

  /// Money: rials returned. Items: how many came back.
  final int amount;

  Map<String, Object?> toJson() => {
    'loan': loanId,
    'date': date,
    'amount': amount,
  };
}

/// The local civil date as `YYYY-MM-DD`.
String civilDateKey(DateTime moment) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${moment.year}-${two(moment.month)}-${two(moment.day)}';
}
