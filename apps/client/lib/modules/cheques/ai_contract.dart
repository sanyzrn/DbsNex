import 'logic.dart';
import 'model.dart';
import 'values.dart';

/// Read-only projection, not an AI connection or permission grant.
class ChequeContextV1 {
  static Map<String, Object?> build(
    List<Cheque> records,
    DateTime today, {
    bool includeNames = false,
    int limit = 12,
  }) {
    if (chequeDay(chequeDayKey(today)) == null || limit < 1 || limit > 20) {
      throw ArgumentError('projection limit');
    }
    final valid = records.where((c) => c.valid).toList();
    final selected = actionableCheques(valid);
    final windows = chequeOutlook(valid, today);
    return {
      'v': 1,
      'asOf': chequeDayKey(today),
      'currency': 'IRR',
      'openCount': selected.length,
      'omittedCount': selected.length > limit ? selected.length - limit : 0,
      'excludedInvalidCount': records.length - valid.length,
      'weeks': [
        for (final w in windows)
          {
            'from': chequeDayKey(w.from),
            'before': chequeDayKey(w.to),
            'outgoingRial': w.outgoing.toString(),
            'expectedIncomingRial': w.incoming.toString(),
          },
      ],
      'items': [
        for (final c in selected.take(limit))
          {
            'ref': c.id,
            'direction': c.direction,
            'purpose': c.purpose,
            'status': c.status,
            'remainingRial': c.remaining.toString(),
            'actionDay': c.actionDay == null
                ? null
                : chequeDayKey(c.actionDay!),
            'nextAction': c.purpose == 'guarantee'
                ? 'reviewGuarantee'
                : c.status == 'bounced'
                ? 'followUpBounced'
                : c.status == 'deposited'
                ? 'checkBankOutcome'
                : c.direction == 'outgoing'
                ? 'prepareFunds'
                : 'followUpCollection',
            if (includeNames) 'party': c.party,
          },
      ],
      'notice': 'User-reported records. Expected receipts are not cleared funds. No bank verification.',
    };
  }
}

/// Validated suggestions for a future host adapter. Never writes a record.
/// Source snippets/confidence are intentionally not persisted automatically.
class ChequeDraftProposalV1 {
  ChequeDraftProposalV1._(this.fields, this.uncertain);
  final Map<String, String> fields;
  final Set<String> uncertain;
  static ChequeDraftProposalV1 parse(Map<String, Object?> raw) {
    if (raw['v'] != 1 ||
        raw['fields'] is! Map ||
        raw['uncertain'] is! List ||
        (raw['uncertain'] as List).length > 7) {
      throw const FormatException('proposal version/shape');
    }
    final fields = <String, String>{};
    for (final e in (raw['fields'] as Map).entries) {
      if (![
            'direction',
            'purpose',
            'amountRial',
            'party',
            'due',
            'bank',
            'sayad',
          ].contains(e.key) ||
          e.value is! String) {
        throw const FormatException('proposal field');
      }
      fields[e.key as String] = e.value as String;
    }
    if (fields.containsKey('direction') &&
            !['incoming', 'outgoing'].contains(fields['direction']) ||
        fields.containsKey('purpose') &&
            !['payment', 'guarantee'].contains(fields['purpose']) ||
        fields.containsKey('amountRial') &&
            chequeAmount(fields['amountRial']) == null ||
        fields.containsKey('due') && chequeDay(fields['due']) == null ||
        fields.containsKey('sayad') &&
            !RegExp(r'^[0-9]{16}$').hasMatch(fields['sayad']!) ||
        ['party', 'bank'].any(
          (k) =>
              fields[k] != null &&
              (fields[k]!.trim().isEmpty || fields[k]!.length > 100),
        )) {
      throw const FormatException('invalid proposal values');
    }
    final uncertain = <String>{};
    for (final key in raw['uncertain'] as List) {
      if (key is! String || !fields.containsKey(key)) {
        throw const FormatException('uncertain field');
      }
      uncertain.add(key);
    }
    return ChequeDraftProposalV1._(
      Map.unmodifiable(fields),
      Set.unmodifiable(uncertain),
    );
  }
}
