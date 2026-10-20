import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'parking_logic.dart';

/// The module's small local helpers: a single-line field that follows the
/// script being typed, and the time and duration formats the rows share.
///
/// Dates a person reads go through the shared `nexModuleDateLabel`, so a
/// Persian reader sees Jalali and an English one Gregorian, following the
/// app's saved calendar. Dates a person types stay civil `yyyy/MM/dd` with
/// the shared calendar button (`NexModuleDateEntry`), and storage stays
/// ISO 8601 instants.
///
/// One-line fields are built inside [NexAutoDirection] (ADR-037); numbers
/// are typed left to right.
class ParkingFields {
  const ParkingFields._();

  // ------------------------------------------------------------ numbers

  /// Two digits with a leading zero, for month, day, hour and minute.
  static String two(int value) => value < 10 ? '0$value' : '$value';

  /// ASCII digits in [text] as the interface's digits — «۱۴۰۵» on the
  /// Persian side, "1405" in English. This is the app's own `nexDigits`
  /// (packages/core), which is not exported to modules, written locally.
  static String digits(BuildContext context, String text) =>
      NexModuleStrings.persian(context)
      ? text.replaceAllMapped(
          RegExp(r'[0-9]'),
          (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
        )
      : text;

  // ------------------------------------------------------------- dates

  /// A time of day, 24-hour.
  static String hm(BuildContext context, DateTime time) =>
      digits(context, '${two(time.hour)}:${two(time.minute)}');

  /// An instant read in full: the date through the shared label — Jalali
  /// for a Persian reader, Gregorian for an English one, following the
  /// person's saved calendar — and the 24-hour time beside it.
  static String when(BuildContext context, DateTime value) {
    final local = value.toLocal();
    return '${nexModuleDateLabel(context, local)} · ${hm(context, local)}';
  }

  // ---------------------------------------------------------- durations

  /// A duration said the short way both languages read it: minutes under
  /// an hour, hours and minutes under a day, days and hours above. A zero
  /// trailing unit is left out — "2 h", not "2 h 0 min".
  static String duration(
    BuildContext context,
    NexModuleStrings strings,
    Duration value,
  ) {
    final t = ParkingLogic.split(value);
    if (t.days > 0) {
      return t.hours > 0
          ? strings(context, 'daysHours', {'d': t.days, 'h': t.hours})
          : strings(context, 'days', {'count': t.days});
    }
    if (t.hours > 0) {
      return t.minutes > 0
          ? strings(context, 'hoursMinutes', {'h': t.hours, 'm': t.minutes})
          : strings(context, 'hours', {'count': t.hours});
    }
    return strings(context, 'minutes', {'count': t.minutes});
  }

  // ------------------------------------------------------------- fields

  /// A single-line field that follows the script being typed.
  static Widget line({
    Key? fieldKey,
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType keyboard = TextInputType.text,
    String? helper,
    Widget? suffix,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) => NexAutoDirection(
    controller: controller,
    builder: (context, direction) => TextField(
      key: fieldKey,
      controller: controller,
      textDirection: direction,
      textAlign: TextAlign.start,
      keyboardType: keyboard,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        suffixIcon: suffix,
      ),
    ),
  );
}
