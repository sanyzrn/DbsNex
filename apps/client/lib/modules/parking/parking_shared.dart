import 'package:nex_client/modules/module_api.dart';

import 'parking_logic.dart';
import 'parking_models.dart';

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

/// Parking's dates and lines in the shared shape (2.8.4).
///
/// What falls due is a parking's paid time running out; a parking already
/// closed has nothing left to fall due, and says so with `done`.
class ParkingShared {
  const ParkingShared(this.sessions);

  /// The module's `session` records.
  final List<ModuleRecord> sessions;

  /// Everything this module has falling due between [from] and [to].
  List<ModuleDue> duesBetween(DateTime from, DateTime to) => [
    for (final record in sessions)
      if (ParkingModels.readDate(record.body, 'expiresAt') case final at?
          when !at.isBefore(from) && !at.isAfter(to))
        ModuleDue(
          id: 'paid-until:${record.id}',
          recordKind: ParkingModels.session,
          recordId: record.id,
          at: at,
          title: _where(record.body),
          kind: 'paid-until',
          done: !ParkingLogic.isActive(record.body),
        ),
  ]..sort((a, b) => a.at.compareTo(b.at));

  /// One line about [record], in the person's own words; null to keep it
  /// out — drafts, journals and searches are the module's own business.
  static ModuleSummary? summarize(ModuleRecord record) {
    final body = record.body;
    if (record.kind == ParkingModels.session) {
      final title = _where(body);
      final detail = [
        ParkingModels.readString(body, 'floor'),
        ParkingModels.readString(body, 'spot'),
        ParkingModels.readString(body, 'landmark'),
      ].where((s) => s.trim().isNotEmpty).join(' · ');
      if (title.isEmpty && detail.isEmpty) return null;
      return ModuleSummary(
        title: title,
        detail: detail.isEmpty ? null : detail,
      );
    }
    if (record.kind == ParkingModels.place) {
      final title = ParkingModels.readString(body, 'place').trim();
      return title.isEmpty ? null : ModuleSummary(title: title);
    }
    return null;
  }

  static String _where(Map<String, Object?> body) {
    final place = ParkingModels.readString(body, 'place').trim();
    return place.isNotEmpty
        ? place
        : ParkingModels.readString(body, 'vehicle').trim();
  }
}
