import 'package:nex_client/modules/module_api.dart';

import 'module.dart' show occasionsStrings;
import 'occasion_math.dart';
import 'occasion_model.dart';

/// Birthdays & occasions in the shared shape (2.8.5), and its glance.
///
/// What falls due is the day each date comes round, in its own calendar. A
/// remembrance is private: its name never leaves the module unasked.
class OccasionsShared {
  const OccasionsShared(this.occasions);

  final List<Occasion> occasions;

  factory OccasionsShared.fromRecords(Iterable<ModuleRecord> records) =>
      OccasionsShared([
        for (final record in records) Occasion.fromRecord(record),
      ]);

  /// Everything this module has falling due between [from] and [to].
  List<ModuleDue> duesBetween(DateTime from, DateTime to) {
    final last = DateTime(to.year, to.month, to.day);
    final years = (last.difference(from).inDays ~/ 365) + 2;
    return [
      for (final occasion in occasions)
        if (!occasion.archived && occasion.title.isNotEmpty)
          for (final day in upcomingDays(occasion, from, years))
            if (!day.date.isAfter(last))
              ModuleDue(
                id: 'occasion:${occasion.id}:${day.date.toIso8601String().substring(0, 10)}',
                recordKind: 'occasion',
                recordId: occasion.id,
                at: DateTime(day.date.year, day.date.month, day.date.day),
                title: occasion.title,
                kind: occasion.kind.name,
                private: occasion.kind == OccasionKind.memorial,
              ),
    ]..sort((a, b) => a.at.compareTo(b.at));
  }

  /// One line about [record], in the person's own words; null to keep it out.
  static ModuleSummary? summarize(ModuleRecord record) {
    if (record.kind != 'occasion') return null;
    final occasion = Occasion.fromRecord(record);
    if (occasion.title.isEmpty) return null;
    return ModuleSummary(
      title: occasion.title,
      detail: occasion.note.trim().isEmpty ? null : occasion.note.trim(),
      private: occasion.kind == OccasionKind.memorial,
    );
  }
}

/// The pinned tile and quick view of Birthdays & occasions (2.8.5): the
/// nearest date and how far off on the tile; the next few in the quick view.
Future<ModuleGlance?> occasionsGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      occasionsStrings.text(l10n, key, args);
  final today = DateTime(now.year, now.month, now.day);
  final dues = OccasionsShared.fromRecords(await store.list('occasion'))
      .duesBetween(today, today.add(const Duration(days: 366)));
  if (dues.isEmpty) return ModuleGlance(headline: t('glanceEmpty'));
  final next = dues.first;
  final month = dues.where((d) => d.at.difference(today).inDays < 31).length;
  return ModuleGlance(
    headline: next.title,
    detail: nexDueWhen(l10n, next.at, today),
    facts: [
      for (final due in dues.take(6))
        ModuleGlanceFact(
          due.title,
          '${nexDueWhen(l10n, due.at, today)} · ${nexReadableDate(due.at, solar: store.solarCalendar, persian: l10n.localeName.startsWith('fa'))}',
          strong: identical(due, next),
        ),
      ModuleGlanceFact(
        t('glanceThisMonth'),
        nexDigits('$month', persian: l10n.localeName.startsWith('fa')),
      ),
    ],
  );
}
