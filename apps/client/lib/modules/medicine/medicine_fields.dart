import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

/// The module's small local helpers: a single-line field that follows the
/// script being typed, number reading tolerant of Persian digits, and the
/// 24-hour time the dose rows share. They exist because the app's own field
/// widgets are not part of `module_api.dart` — see README → Platform
/// requests. Absolute dates a person reads go through the shared
/// `nexModuleDateLabel`, so a Persian reader on the solar calendar sees a
/// Jalali day in Persian digits and an English one the civil day; storage
/// stays civil ISO 8601.
class MedicineFields {
  const MedicineFields._();

  /// Two digits with a leading zero, for month, day, hour and minute.
  static String two(int value) => value < 10 ? '0$value' : '$value';

  /// ASCII digits in [text] as the interface's digits — «۱۴۰۵» on the
  /// Persian side, "1405" in English. The app's own `nexDigits`
  /// (packages/core) is not exported to modules, so it lives here.
  static String digits(BuildContext context, String text) =>
      NexModuleStrings.persian(context)
      ? text.replaceAllMapped(
          RegExp(r'[0-9]'),
          (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
        )
      : text;

  /// A time of day, 24-hour.
  static String hm(BuildContext context, DateTime time) =>
      digits(context, '${two(time.hour)}:${two(time.minute)}');

  /// A single-line field that follows the script being typed.
  static Widget line({
    Key? fieldKey,
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType keyboard = TextInputType.text,
    String? helper,
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
      ),
    ),
  );

  /// A number field: left to right, digits only expected, but the reader
  /// accepts Persian digits too.
  static Widget number({
    Key? fieldKey,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helper,
    ValueChanged<String>? onChanged,
  }) => TextField(
    key: fieldKey,
    controller: controller,
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.start,
    keyboardType: TextInputType.number,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
    ),
  );
}
