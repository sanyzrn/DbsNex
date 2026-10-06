import 'package:flutter/material.dart';

import '../platform/nex_services.dart';
import 'nex_dialog.dart';
import 'reminder_wheel.dart';

/// Asks when the note being written should arrive — the capture sheet's
/// held Send. Null when the sheet was dismissed.
///
/// The reminder's own wheels in [ReminderWheel.schedule] mode: the same
/// gesture for "when", whatever the "when" is for.
Future<DateTime?> nexPickScheduleTime({
  required BuildContext context,
  required NexServices services,
}) {
  final now = DateTime.now();
  return nexShowSheet<DateTime>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ReminderWheel(
        schedule: true,
        note: null,
        now: now,
        solarCalendar: services.solarCalendar,
        onSubmit: (when, _) => Navigator.pop(sheetContext, when),
      ),
    ),
  );
}
