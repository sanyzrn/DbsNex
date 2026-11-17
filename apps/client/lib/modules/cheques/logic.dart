import 'model.dart';
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
    for (final c in rows) {
      if (!c.valid ||
          c.closed ||
          c.purpose != 'payment' ||
          c.due == null ||
          c.due!.isBefore(from) ||
          !c.due!.isBefore(to)) {
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
