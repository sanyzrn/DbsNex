import 'package:nex_client/modules/module_api.dart';

import 'logic.dart';
import 'models.dart';
import 'units.dart';

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

/// Maintenance's dates and lines in the shared shape (2.8.4).
///
/// What falls due: a car's insurance and inspection expiry, and each
/// service whose next date its rule knows (a rule counted only in km or
/// hours has no date, so it is not on a calendar). Archived assets and
/// malformed records are left out.
class MaintenanceShared {
  const MaintenanceShared({
    required this.assets,
    required this.events,
    required this.rules,
    this.readings = const [],
  });

  /// From the module's records, as the store lists them.
  factory MaintenanceShared.fromRecords(
    Map<String, List<ModuleRecord>> byKind,
  ) {
    List<ModuleRecord> of(String kind) => byKind[kind] ?? const [];
    return MaintenanceShared(
      assets: [
        for (final r in of('asset')) MaintenanceAsset.fromBody(r.id, r.body),
      ],
      events: [
        for (final r in of('event')) ServiceEvent.fromBody(r.id, r.body),
      ],
      rules: [for (final r in of('rule')) ?IntervalRule.fromBody(r.id, r.body)],
      readings: [
        for (final r in of('reading'))
          ?MaintenanceReading.fromBody(r.id, r.body),
      ],
    );
  }

  final List<MaintenanceAsset> assets;
  final List<ServiceEvent> events;
  final List<IntervalRule> rules;
  final List<MaintenanceReading> readings;

  /// Everything this module has falling due between [from] and [to].
  List<ModuleDue> duesBetween(DateTime from, DateTime to) {
    bool inside(DateTime at) => !at.isBefore(from) && !at.isAfter(to);
    final out = <ModuleDue>[];
    for (final asset in assets) {
      if (!asset.valid || asset.archived) continue;
      if (asset.type == 'car') {
        for (final (kind, at) in [
          ('insurance-expiry', asset.insuranceExpiresAt),
          ('inspection-expiry', asset.inspectionExpiresAt),
        ]) {
          if (at == null || !inside(dayOf(at))) continue;
          out.add(
            ModuleDue(
              id: '$kind:${asset.id}',
              recordKind: 'asset',
              recordId: asset.id,
              at: dayOf(at),
              title: asset.nickname,
              kind: kind,
            ),
          );
        }
      }
      for (final standing in ruleStandings(
        asset,
        events,
        rules,
        from,
        readings: readings,
      )) {
        final at = standing.earliestDue.date;
        if (at == null || !inside(dayOf(at))) continue;
        out.add(
          ModuleDue(
            id: 'service:${standing.rule.id}',
            recordKind: 'rule',
            recordId: standing.rule.id,
            at: dayOf(at),
            title: '${standing.rule.task} · ${asset.nickname}',
            kind: 'service',
          ),
        );
      }
    }
    return out..sort((a, b) => a.at.compareTo(b.at));
  }

  /// One line about [record], in the person's own words; null to keep it
  /// out — readings are numbers only, and drafts and journals are the
  /// module's own business.
  static ModuleSummary? summarize(ModuleRecord record) {
    final body = record.body;
    String? text(String key) {
      final value = body[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final title = switch (record.kind) {
      'asset' => text('nickname'),
      'event' || 'rule' => text('task'),
      'fuel' => text('rate'),
      'fuel_rate' => text('name'),
      _ => null,
    };
    if (title == null) return null;
    final detail = switch (record.kind) {
      'asset' => text('model'),
      'event' => [
        text('provider'),
        text('notes'),
      ].whereType<String>().join(' · '),
      'fuel' => text('notes'),
      _ => null,
    };
    return ModuleSummary(
      title: title,
      detail: detail == null || detail.isEmpty ? null : detail,
    );
  }
}
