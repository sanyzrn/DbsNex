import 'package:nex_client/modules/module_api.dart';

import 'parking_logic.dart';
import 'parking_models.dart';

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
