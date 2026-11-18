/// The shapes every module shares with the rest of Nex (`docs/18-module-kit.md`,
/// "Shared across modules", rules 1 and 4). They lived as copies in each
/// module's folder until 2.8.4, when the home screen began to read them; the
/// copies were replaced in the same change.
library;

/// Something a module has falling due: a cheque, an instalment, a dose, an
/// insurance expiry, a payment day.
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

  /// Stable, so the same item is the same item next time.
  final String id;

  /// The record it comes from, to open it.
  final String recordKind;
  final String recordId;

  /// When it falls due: local; a date-only item at midnight.
  final DateTime at;

  /// What it is, in the person's own words where possible.
  final String title;

  /// The module's word for it (`cheque-in`, `dose`, …).
  final String kind;

  /// Money, when there is any: positive in, negative out.
  final int? amountRial;

  /// Already paid, taken or cleared.
  final bool done;

  /// Health or money detail, shown only discreetly.
  final bool private;
}

/// One line about a record, in the person's own words.
class ModuleSummary {
  const ModuleSummary({required this.title, this.detail, this.private = false});

  final String title;
  final String? detail;

  /// Health or money: never shown without the person opting in.
  final bool private;
}
