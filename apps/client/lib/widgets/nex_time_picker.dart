import 'package:flutter/material.dart';

/// The time picker, shown the way the phone's own clock shows it.
///
/// Nex scales its type from a setting in Settings, applied app-wide in
/// `app.dart`. That multiplier belongs on Nex's own surfaces and not here: the
/// Material time picker lays its dial out at fixed sizes and then draws numbers
/// into it, so a scale either side of 1 leaves them cramped against the ring or
/// spilling over it. The result is recognisably the same dialog and visibly not
/// the one in the clock app — which is the report this fixes.
///
/// So the dialog is handed the *platform's* text scaling, read straight from
/// the view, rather than Nex's composed value. Not `TextScaler.noScaling`,
/// which would be wrong in the other direction: someone who enlarged type
/// system-wide did so for a reason, and that reason applies to a dial full of
/// two-digit numbers more than to anything else in the app.
///
/// Everything else is left alone — 12-hour or 24-hour, the colours, the shapes.
/// Those already follow the device and the theme, and pinning them here would
/// be a second way to drift from the system rather than a way back to it.
Future<TimeOfDay?> nexPickTime(
  BuildContext context, {
  required TimeOfDay initial,
}) {
  return showTimePicker(
    context: context,
    initialTime: initial,
    // The dial, not the keyboard. Keyboard entry is one tap away inside the
    // dialog for anyone who prefers it, and opening on it would be the app
    // choosing differently from every alarm this person has ever set.
    initialEntryMode: TimePickerEntryMode.dial,
    builder: (context, child) {
      final platform = MediaQueryData.fromView(View.of(context));
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: platform.textScaler),
        child: child!,
      );
    },
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
}) {
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    builder: (context, child) {
      final platform = MediaQueryData.fromView(View.of(context));
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: platform.textScaler),
        child: child!,
      );
    },
  );
}
