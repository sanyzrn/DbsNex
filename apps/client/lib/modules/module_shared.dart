/// The shapes every module shares with the rest of Nex (`docs/18-module-kit.md`,
/// "Shared across modules", rules 1 and 4). They lived as copies in each
/// module's folder until 2.8.4, when the home screen began to read them; the
/// copies were replaced in the same change.
library;

import 'package:nex_core/nex_core.dart' show nexDigits;

import '../l10n/app_localizations.dart';

/// «today», «tomorrow», «in 3 days» or «2 days late», counted in civil days
/// (2.8.5: in the kit, for the modules' glances and the home screen alike).
String nexDueWhen(AppLocalizations l10n, DateTime at, DateTime today) {
  final days = DateTime.utc(
    at.year,
    at.month,
    at.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (days < 0) return l10n.toolDatesLate(-days);
  if (days == 0) return l10n.toolDatesToday;
  if (days == 1) return l10n.toolDatesTomorrow;
  return l10n.toolDatesIn(days);
}

/// Where a whole-toman figure's thousands separators go, compiled once —
/// every money line a module shows pays this once, not one compile each.
final RegExp _tomanGroups = RegExp(r'\B(?=(\d{3})+(?!\d))');

/// Whole rials said in tomans, grouped, in the page's digits: «۱۲,۵۰۰ تومان».
/// A tenth of a toman is kept, never rounded away.
String nexTomanText(BigInt rial, AppLocalizations l10n) {
  final negative = rial.isNegative;
  final abs = rial.abs();
  final whole = (abs ~/ BigInt.from(10)).toString().replaceAllMapped(
    _tomanGroups,
    (_) => ',',
  );
  final tenth = abs % BigInt.from(10);
  final persian = l10n.localeName.startsWith('fa');
  final number =
      '${negative ? '−' : ''}$whole${tenth == BigInt.zero ? '' : '${persian ? '٫' : '.'}$tenth'}';
  return l10n.moneyToman(nexDigits(number, persian: persian));
}

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
    this.passes = false,
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

  /// A day rather than a task (2.8.6): a birthday or a warranty's end is
  /// over once it has gone by, never «17 days late» — nothing is left to do.
  final bool passes;

  /// Whether nothing is left to show for it on [today]: done, or a day
  /// that has gone by.
  bool isOver(DateTime today) =>
      done ||
      (passes && at.isBefore(DateTime(today.year, today.month, today.day)));
}

/// One line about a record, in the person's own words.
class ModuleSummary {
  const ModuleSummary({required this.title, this.detail, this.private = false});

  final String title;
  final String? detail;

  /// Health or money: never shown without the person opting in.
  final bool private;
}

/// What a module says about itself at a glance (2.8.5): two short lines for
/// its pinned tile on the home screen, and a few facts for the quick view a
/// tap on that tile opens before the module itself.
///
/// Every number is the person's own, counted on the phone; nothing here is
/// sent anywhere. A module whose data is money or health keeps amounts off
/// the tile — the home screen is seen over a shoulder — and may show them
/// in [facts], which only open on a tap.
class ModuleGlance {
  const ModuleGlance({
    required this.headline,
    this.detail,
    this.progress,
    this.facts = const [],
  });

  /// The tile's first line: the one thing worth knowing now.
  final String headline;

  /// The tile's second line, when there is one.
  final String? detail;

  /// How far along today is, 0 to 1, when the module counts toward
  /// something; a ring round its mark. Null draws none.
  final double? progress;

  /// The quick view's rows, most useful first.
  final List<ModuleGlanceFact> facts;
}

/// One row of a module's quick view: a label and its value.
class ModuleGlanceFact {
  const ModuleGlanceFact(this.label, this.value, {this.strong = false});

  final String label;
  final String value;

  /// Drawn a little stronger: the row the eye should land on.
  final bool strong;
}
