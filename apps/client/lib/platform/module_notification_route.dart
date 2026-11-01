import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../modules/module_dates.dart';
import '../modules/module_registry.dart';
import '../modules/nex_stored_module.dart';
import '../modules/nex_module_store.dart';
import '../modules/habits/habit_detail_screen.dart';
import '../modules/occasions/occasion_detail.dart';
import '../modules/lent_borrowed/loan_detail_screen.dart';
import '../modules/maintenance/asset_page.dart';
import '../modules/medicine/medicine_detail.dart';
import '../modules/warranty/warranty_detail.dart';
import '../modules/parking/parking_detail.dart';
import '../modules/words/words_review_page.dart';
import '../screens/cycle_screen.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_dialog.dart';
import 'module_notification.dart';
import 'nex_preferences.dart';
import 'nex_services.dart';

/// One routing rule for cold and warm taps. No module is enabled by a tap.
Future<void> nexOpenModuleNotification(
  BuildContext context, {
  required NexModuleTarget target,
  required NexServices services,
  required NexPreferences preferences,
}) async {
  final module = nexModules.where((m) => m.id == target.module).firstOrNull;
  if (module == null || !module.available || !module.isOn(preferences)) {
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).moduleNotificationUnavailable,
      kind: NexBannerKind.failed,
    );
    return;
  }
  Widget page = module.open(services: services, preferences: preferences);
  if (target.module == 'cycle') {
    page = CycleScreen(
      services: services,
      preferences: preferences,
      reminderKey: target.kind,
      reminderDay: DateTime.tryParse(target.day),
    );
  }
  var sheet = false;
  var missing = false;
  if (module is NexStoredModule &&
      target.kind.isNotEmpty &&
      target.id.isNotEmpty) {
    final record = await services.moduleRecord(
      module.id,
      target.kind,
      target.id,
    );
    if (!context.mounted) return;
    if (record == null || record.body['archived'] == true) {
      missing = true;
    } else {
      final store = NexModuleStore(services, module.id);
      final detail = switch ((module.id, record.kind)) {
        ('habits', 'habit') => HabitDetailScreen(
          store: store,
          habitId: record.id,
          startLogAmount: target.progress,
        ),
        ('occasions', 'occasion') => OccasionDetailScreen(
          store: store,
          occasionId: record.id,
        ),
        ('lent_borrowed', 'loan') => LoanDetailScreen(
          store: store,
          loanId: record.id,
        ),
        ('parking', 'session') => ParkingDetailPage(
          store: store,
          sessionId: record.id,
        ),
        ('words', 'settings') => WordsReviewPage(store: store),
        ('maintenance', 'asset') => AssetPage(store: store, assetId: record.id),
        ('medicine', 'medicine') => MedicineDetailSheet(
          store: store,
          record: record,
        ),
        ('warranty', 'warranty') => WarrantyDetailSheet(
          store: store,
          record: record,
        ),
        _ => null,
      };
      if (detail != null) {
        sheet = module.id == 'medicine' || module.id == 'warranty';
        page = NexModuleCalendar(
          solar: preferences.solarCalendar,
          child: detail,
        );
      }
    }
  }
  if (!context.mounted) return;
  if (missing) {
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).moduleNotificationItemMissing,
      kind: NexBannerKind.failed,
    );
  }
  final destination = page;
  if (sheet) {
    await nexShowSheet<void>(context: context, builder: (_) => destination);
  } else {
    await Navigator.of(
      context,
    ).push(NexPageRoute<void>(builder: (_) => destination));
  }
}
