import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'warranty_logic.dart';
import 'warranty_strings.dart';

/// The module's small local helpers: fields that follow the typed script,
/// number reading tolerant of Persian digits, and the money and date
/// formats the rows share. They exist because the app's own field and
/// date-picker widgets are not part of `module_api.dart` — see README →
/// Platform requests. Every date a person reads is shown on their saved
/// calendar (Jalali for a Persian reader) through the shared label; entry
/// stays civil, and the shared calendar button picks the day.
class WarrantyFields {
  const WarrantyFields._();

  /// ASCII digits in [text] as the interface's digits, grouped in threes.
  static String digits(BuildContext context, String text) {
    return NexModuleStrings.persian(context)
        ? text.replaceAllMapped(
            RegExp(r'[0-9]'),
            (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
          )
        : text;
  }

  /// A civil day as the module shows it, on the saved calendar and in the
  /// interface's digits. The day is rebuilt as a local one first, so a
  /// date stored at UTC midnight never reads as the day before it was
  /// written, west of Greenwich.
  static String dayLabel(BuildContext context, DateTime day) =>
      nexModuleDateLabel(context, DateTime(day.year, day.month, day.day));

  /// An instant (a claim note's `at`) on the person's calendar: the local
  /// day it happened, never the stored UTC one.
  static String instantLabel(BuildContext context, DateTime at) =>
      nexModuleDateLabel(context, at.toLocal());

  /// The amount in both readings, rial first, exactly converted — never
  /// a rounded toman.
  static String money(BuildContext context, int rials) {
    final remainder = rials % 10;
    final toman =
        '${WarrantyLogic.grouped(rials ~/ 10)}${remainder == 0 ? '' : '.$remainder'}';
    return '${digits(context, WarrantyLogic.grouped(rials))} ${warrantyStrings(context, 'rials')}'
        '  ·  ${digits(context, toman)} ${warrantyStrings(context, 'tomans')}';
  }

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
  }) => NexAutoDirection(
    controller: controller,
    builder: (context, direction) => TextField(
      key: fieldKey,
      controller: controller,
      textDirection: direction,
      textAlign: TextAlign.start,
      keyboardType: keyboard,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        suffixIcon: suffix,
      ),
    ),
  );

  /// A number field: left to right, because numbers are.
  static Widget number({
    Key? fieldKey,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helper,
    Widget? suffix,
    bool decimal = false,
  }) => TextField(
    key: fieldKey,
    controller: controller,
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.start,
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      suffixIcon: suffix,
    ),
  );
}
