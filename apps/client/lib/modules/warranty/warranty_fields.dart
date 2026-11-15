import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'warranty_logic.dart';
import 'warranty_models.dart';
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
        ? nexDigits(text, persian: true)
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

  /// How long the cover has left — or how long ago it ended — in the one
  /// wording the list and the purchase's own page share, so they cannot
  /// drift apart.
  static String remaining(BuildContext context, DateTime end, DateTime now) {
    final status = WarrantyLogic.statusOf(end, now);
    if (status.expired) {
      return status.daysLeft == -1
          ? warrantyStrings(context, 'endedYesterday')
          : warrantyStrings(context, 'expiredDaysAgo', {
              'count': -status.daysLeft,
            });
    }
    if (status.daysLeft == 0) return warrantyStrings(context, 'endsToday');
    if (status.daysLeft == 1) return warrantyStrings(context, 'oneDayLeft');
    return warrantyStrings(context, 'daysLeft', {'count': status.daysLeft});
  }

  /// The words for a stored cover kind, or '' when none was chosen.
  static String coverKind(BuildContext context, String kind) => switch (kind) {
    WarrantyModels.coverCompany => warrantyStrings(context, 'coverCompany'),
    WarrantyModels.coverSeller => warrantyStrings(context, 'coverSeller'),
    WarrantyModels.coverAfterSales => warrantyStrings(
      context,
      'coverAfterSales',
    ),
    _ => '',
  };

  /// What the chosen cover kind means, in one line — the difference between
  /// a company warranty, the shop's own guarantee and after-sales service.
  static String coverKindHint(
    BuildContext context,
    String kind,
  ) => switch (kind) {
    WarrantyModels.coverCompany => warrantyStrings(context, 'coverCompanyHint'),
    WarrantyModels.coverSeller => warrantyStrings(context, 'coverSellerHint'),
    WarrantyModels.coverAfterSales => warrantyStrings(
      context,
      'coverAfterSalesHint',
    ),
    _ => '',
  };

  /// The words for who the device is registered to, or '' when unknown.
  static String registry(BuildContext context, String owner) => switch (owner) {
    WarrantyModels.registryMine => warrantyStrings(
      context,
      'registryMineValue',
    ),
    WarrantyModels.registryOther => warrantyStrings(
      context,
      'registryOtherValue',
    ),
    _ => '',
  };

  /// A value that must read left to right whatever the interface language
  /// is: a serial, an IMEI, a card number, a phone number, an invoice id.
  static Widget ltr(String text, {TextStyle? style}) => Text(
    text,
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.start,
    style: style,
  );

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

  /// A value that is always left to right — a serial, an IMEI, a card or a
  /// phone number — so the digits never reorder in a Persian interface.
  static Widget ltrLine({
    Key? fieldKey,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helper,
  }) => TextField(
    key: fieldKey,
    controller: controller,
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.start,
    keyboardType: TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
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
