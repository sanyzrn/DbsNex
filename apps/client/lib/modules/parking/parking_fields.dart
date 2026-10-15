import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'parking_logic.dart';

/// The module's small local helpers: a single-line field that follows the
/// script being typed, a transparent Gregorian date/time entry, and the
/// date and duration formats the rows share. They exist because the app's
/// own field, date-picker and calendar helpers are not part of
/// `module_api.dart` — see README → Platform requests.
///
/// One-line fields are built inside [NexAutoDirection] (ADR-037); numbers
/// are typed left to right. Dates are Gregorian and say so, because the
/// app's Jalali formatter is not reachable from here and a Gregorian date
/// mislabelled as Jalali is worse than an honest Gregorian one.
class ParkingFields {
  const ParkingFields._();

  // ------------------------------------------------------------ numbers

  /// Persian and Arabic digits typed in a number field, read as the
  /// numbers they are — «۱۲» is 12.
  static int? looseInt(String text) {
    final mapped = text.characters.map((c) {
      for (var d = 0; d < 10; d++) {
        if (c == '۰۱۲۳۴۵۶۷۸۹'[d] || c == '٠١٢٣٤٥٦٧٨٩'[d]) {
          return '$d';
        }
      }
      return c;
    }).join();
    return int.tryParse(mapped.trim());
  }

  /// A decimal typed with Persian digits, a Persian «٫» or a dot.
  static double? looseDouble(String text) {
    final mapped = text.characters
        .map((c) {
          for (var d = 0; d < 10; d++) {
            if (c == '۰۱۲۳۴۵۶۷۸۹'[d] || c == '٠١٢٣٤٥٦٧٨٩'[d]) {
              return '$d';
            }
          }
          if (c == '٫') {
            return '.';
          }
          return c;
        })
        .join()
        .trim();
    return double.tryParse(mapped);
  }

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

  /// The date as the module shows it: Gregorian, zero padded.
  static String ymd(BuildContext context, DateTime date) =>
      digits(context, '${date.year}/${two(date.month)}/${two(date.day)}');

  /// A time of day, 24-hour.
  static String hm(BuildContext context, DateTime time) =>
      digits(context, '${two(time.hour)}:${two(time.minute)}');

  /// When the parking began: today says its time, another day its date
  /// and time.
  static String startedAt(BuildContext context, DateTime value) => digits(
    context,
    '${ymd(context, value)} '
    '${two(value.hour)}:${two(value.minute)}',
  );

  // ---------------------------------------------------------- durations

  /// A duration said the short way both languages read it: minutes under
  /// an hour, hours and minutes under a day, days and hours above.
  static String duration(
    BuildContext context,
    NexModuleStrings strings,
    Duration value,
  ) {
    final t = ParkingLogic.split(value);
    if (t.days > 0) {
      return strings(context, 'daysHours', {'d': t.days, 'h': t.hours});
    }
    if (t.hours > 0) {
      return strings(context, 'hoursMinutes', {'h': t.hours, 'm': t.minutes});
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
