import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'warranty_logic.dart';
import 'warranty_strings.dart';

/// The module's small local helpers: fields that follow the typed script,
/// number reading tolerant of Persian digits, and the date and money
/// formats the rows share. They exist because the app's own field and
/// date-picker widgets are not part of `module_api.dart` — see README →
/// Platform requests. Dates are Gregorian and say so.
class WarrantyFields {
  const WarrantyFields._();

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

  /// Two digits with a leading zero.
  static String two(int value) => value < 10 ? '0$value' : '$value';

  /// ASCII digits in [text] as the interface's digits, grouped in threes.
  static String digits(BuildContext context, String text) {
    return NexModuleStrings.persian(context)
        ? text.replaceAllMapped(
            RegExp(r'[0-9]'),
            (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
          )
        : text;
  }

  /// A date as the module shows it: Gregorian, zero padded, grouped
  /// digits in the interface's script.
  static String ymd(BuildContext context, DateTime date) =>
      digits(context, '${date.year}/${two(date.month)}/${two(date.day)}');

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
