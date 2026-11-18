import 'package:nex_client/modules/module_api.dart';

import 'loan_math.dart';
import 'loan_model.dart';
import 'split_model.dart';

/// Something of this module's falling due, in the shape every module uses
/// for the shared calendar (docs/18, rule 1). Defined here until the kit
/// provides it.
class ModuleDue {
  const ModuleDue({
    required this.id,
    required this.recordKind,
    required this.recordId,
    required this.at,
    required this.title,
    required this.kind,
    this.amountRial,
    this.done = false,
    this.private = false,
  });

  final String id;
  final String recordKind;
  final String recordId;
  final DateTime at;
  final String title;
  final String kind;
  final int? amountRial;
  final bool done;
  final bool private;
}

/// One line about a record, for the search and the brief later (docs/18,
/// rule 4). Defined here until the kit provides it.
class ModuleSummary {
  const ModuleSummary({required this.title, this.detail, this.private = false});

  final String title;
  final String? detail;
  final bool private;
}

/// Lent & borrowed in the shared shape (2.8.4).
///
/// What falls due is a loan's due date; its amount is what is still out —
/// coming in for what was lent, going out for what was borrowed — and only
/// in rials (a loan in another currency, or of a thing, has none). Money is
/// private: a calendar shows it only discreetly.
///
/// The other party stays a plain `person` string, not the shared
/// `{"name": …}` object (rule 3): people's records already say it that way,
/// and a live module's fields are never reshaped (rule 5).
class LoanShared {
  const LoanShared(this.loans, this.returns);

  final List<Loan> loans;
  final List<LoanReturn> returns;

  /// Everything this module has falling due between [from] and [to].
  List<ModuleDue> duesBetween(DateTime from, DateTime to) {
    final dues = <ModuleDue>[];
    for (final loan in loans) {
      final at = _civil(loan.due);
      if (at == null || at.isBefore(from) || at.isAfter(to)) continue;
      final standing = LoanMath.standing(loan, returns);
      final rials = loan.kind == LoanKind.money && loan.currency == 'IRR'
          ? standing.outstanding
          : null;
      final lent = loan.direction == LoanDirection.lent;
      dues.add(
        ModuleDue(
          id: 'due:${loan.id}',
          recordKind: 'loan',
          recordId: loan.id,
          at: at,
          title: loan.kind == LoanKind.item && loan.what.trim().isNotEmpty
              ? '${loan.person} · ${loan.what.trim()}'
              : loan.person,
          kind: lent ? 'loan-lent' : 'loan-borrowed',
          amountRial: rials == null ? null : (lent ? rials : -rials),
          done: standing.outstanding == 0,
          private: true,
        ),
      );
    }
    return dues..sort((a, b) => a.at.compareTo(b.at));
  }

  /// One line about [record], in the person's own words; null to keep it
  /// out — returns, settings, drafts and the card book are not for search.
  static ModuleSummary? summarize(ModuleRecord record) {
    switch (record.kind) {
      case 'loan':
        final loan = Loan.fromRecord(record);
        final detail = [
          loan.what.trim(),
          loan.note.trim(),
        ].where((s) => s.isNotEmpty).join(' · ');
        return ModuleSummary(
          title: loan.person,
          detail: detail.isEmpty ? null : detail,
          private: true,
        );
      case 'split':
        final split = LoanSplit.fromRecord(record);
        if (split.title.trim().isEmpty) return null;
        return ModuleSummary(
          title: split.title.trim(),
          detail: split.people.join(' · '),
          private: true,
        );
    }
    return null;
  }

  static DateTime? _civil(String? date) {
    if (date == null) return null;
    final parts = date.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}
