import 'model.dart';
import 'dues.dart';
import 'values.dart';

List<Cheque> actionableCheques(Iterable<Cheque> rows) =>
    rows.where((c) => c.valid && !c.closed).toList()..sort((a, b) {
      final da = a.actionDay, db = b.actionDay;
      if (da == null) return db == null ? a.id.compareTo(b.id) : 1;
      if (db == null) return -1;
      final compared = da.compareTo(db);
      return compared == 0 ? a.id.compareTo(b.id) : compared;
    });

class ChequeWindow {
  ChequeWindow(this.from, this.to, Iterable<Cheque> rows) {
    for (final due in _cashDues(rows, from, to)) {
      _add(due.cheque);
    }
  }

  ChequeWindow._(this.from, this.to);
  final DateTime from, to;
  final List<Cheque> items = [];
  BigInt incoming = BigInt.zero, outgoing = BigInt.zero;

  void _add(Cheque cheque) {
    items.add(cheque);
    if (cheque.direction == 'outgoing') {
      outgoing += cheque.remaining;
    } else {
      incoming += cheque.remaining;
    }
  }
}

Iterable<({Cheque cheque, DateTime day})> _cashDues(
  Iterable<Cheque> rows,
  DateTime start,
  DateTime end,
) sync* {
  if (!end.isAfter(start)) return;
  final snapshot = ChequeDues(rows);
  final ids = {
    for (final c in snapshot.rows)
      c.recordKind == 'plan' ? c.id : 'cheque:${c.id}': c,
  };
  for (final due in snapshot.duesBetween(
    start,
    DateTime(end.year, end.month, end.day - 1),
  )) {
    if (!due.done && due.kind != 'cheque-review') {
      yield (cheque: ids[due.id]!, day: due.at);
    }
  }
}

List<ChequeWindow> chequeOutlook(List<Cheque> rows, DateTime today) {
  DateTime start(int week) =>
      DateTime(today.year, today.month, today.day + 7 * week);
  final windows = [
    for (var i = 0; i < 4; i++) ChequeWindow._(start(i), start(i + 1)),
  ];
  for (final (:cheque, :day) in _cashDues(rows, start(0), start(4))) {
    windows[chequeDaysBetween(today, day) ~/ 7]._add(cheque);
  }
  return windows;
}

bool chequeOverdue(Cheque c, DateTime today) =>
    c.valid &&
    !c.closed &&
    c.actionDay != null &&
    chequeDaysBetween(today, c.actionDay!) < 0;
