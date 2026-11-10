import 'package:flutter/material.dart';

import 'persian_date_picker.dart';
import 'nex_dialog.dart';

/// The platform's own text scale, without the app's setting on it.
///
/// Nex scales its type from a setting in Settings, applied app-wide in
/// `app.dart`. That multiplier belongs on Nex's own surfaces and not here: the
/// Material pickers lay their dial and month grid out at fixed sizes and then
/// draw numbers into them, so a scale either side of 1 leaves them cramped
/// against the rings or spilling over them. The result is recognisably the
/// same dialog and visibly not the one in the clock app — which is the report
/// this fixes.
///
/// So the dialog is handed the *platform's* text scaling, read straight from
/// the view, rather than Nex's composed value. Not `TextScaler.noScaling`,
/// which would be wrong in the other direction: someone who enlarged type
/// system-wide did so for a reason, and that reason applies to a dial full of
/// two-digit numbers more than to anything else in the app.
///
/// Everything else is left alone — 12-hour or 24-hour, the colours, the
/// shapes, the keyboard entry one tap away. Those already follow the device
/// and the theme, and pinning them here would be a second way to drift from
/// the system rather than a way back to it.
Widget _platformScale(BuildContext context, Widget child) {
  final platform = MediaQueryData.fromView(View.of(context));
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: platform.textScaler),
    child: child,
  );
}

/// The time picker, shown the way the phone's own clock shows it.
///
/// The dialog's contents are the clock app's own, untouched; what changed is
/// the road it arrives by: [nexShowDialog], so it rises a little and settles
/// in on the app's beat and scrim, like every question this app asks — not
/// Flutter's 150ms fade over a raw black54, which nothing else here does.
Future<TimeOfDay?> nexPickTime(
  BuildContext context, {
  required TimeOfDay initial,
}) {
  return nexShowDialog<TimeOfDay>(
    context: context,
    builder: (dialogContext) => _platformScale(
      dialogContext,
      TimePickerDialog(
        initialTime: initial,
        // The dial, not the keyboard. Keyboard entry is one tap away inside the
        // dialog for anyone who prefers it, and opening on it would be the app
        // choosing differently from every alarm this person has ever set.
        initialEntryMode: TimePickerEntryMode.dial,
      ),
    ),
  );
}

/// The date picker, for the same reason and with the same fix.
///
/// A month grid is as fixed in its geometry as a dial is: seven columns of
/// two-digit numbers that have nowhere to go when the type around them grows.
Future<DateTime?> nexPickDate(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
  bool solar = false,
}) {
  if (solar) {
    return nexShowDialog<DateTime>(
      context: context,
      builder: (_) =>
          PersianDatePicker(initial: initial, first: first, last: last),
    );
  }
  // The same clamp showDatePicker used to do before handing the date over,
  // so a caller's rounding at a boundary still opens on a day the calendar
  // can show.
  final shown = initial.isBefore(first)
      ? first
      : initial.isAfter(last)
      ? last
      : initial;
  return nexShowDialog<DateTime>(
    context: context,
    builder: (dialogContext) => _platformScale(
      dialogContext,
      DatePickerDialog(initialDate: shown, firstDate: first, lastDate: last),
    ),
  );
}
