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
    final snapshot = rows.toList();
    final ids = ChequeDues(snapshot)
        .duesBetween(from, DateTime(to.year, to.month, to.day - 1))
        .where((d) => !d.done && d.kind != 'cheque-review')
        .map((d) => d.id)
        .toSet();
    for (final c in snapshot) {
      if (!ids.contains(c.recordKind == 'plan' ? c.id : 'cheque:${c.id}')) {
        continue;
      }
      items.add(c);
      if (c.direction == 'outgoing') {
        outgoing += c.remaining;
      } else {
        incoming += c.remaining;
      }
    }
  }
  final DateTime from, to;
  final List<Cheque> items = [];
  BigInt incoming = BigInt.zero, outgoing = BigInt.zero;
}

List<ChequeWindow> chequeOutlook(List<Cheque> rows, DateTime today) => [
  for (var i = 0; i < 4; i++)
    ChequeWindow(
      DateTime(today.year, today.month, today.day + 7 * i),
      DateTime(today.year, today.month, today.day + 7 * (i + 1)),
      rows,
    ),
];
bool chequeOverdue(Cheque c, DateTime today) =>
    c.valid &&
    !c.closed &&
    c.actionDay != null &&
    chequeDaysBetween(today, c.actionDay!) < 0;
