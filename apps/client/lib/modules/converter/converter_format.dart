import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'converter_date.dart';
import 'converter_number.dart';
import 'converter_sizes.dart';
import 'converter_strings.dart';
import 'converter_units.dart';

/// Writing the module's numbers and dates in the reader's language and
/// digits. One place, so a date in a hero, a row and a record all read the
/// same.

bool converterIsPersian(BuildContext context) =>
    NexModuleStrings.persian(context);

String converterText(
  BuildContext context,
  String key, [
  Map<String, Object?> args = const {},
]) => converterStrings(context, key, args);

/// «۲۲ آبان ۱۴۰۵» / «22 Aban 1405» — a day, its month in words, its year.
String converterDateLabel(BuildContext context, ConverterDate date) {
  final month = converterMonthName(context, date.calendar, date.month);
  return nexDigits(
    '${date.day} $month ${date.year}',
    persian: converterIsPersian(context),
  );
}

/// The calendar's own name: «شمسی», «میلادی», «قمری».
String converterCalendarName(
  BuildContext context,
  ConverterCalendar calendar,
) => converterText(context, switch (calendar) {
  ConverterCalendar.solar => 'calSolar',
  ConverterCalendar.gregorian => 'calGregorian',
  ConverterCalendar.lunar => 'calLunar',
});

/// The month's name in the calendar it belongs to, in the reader's language.
String converterMonthName(
  BuildContext context,
  ConverterCalendar calendar,
  int month,
) {
  switch (calendar) {
    case ConverterCalendar.solar:
      return nexModuleMonthName(context, solar: true, month: month);
    case ConverterCalendar.gregorian:
      return nexModuleMonthName(context, solar: false, month: month);
    case ConverterCalendar.lunar:
      return converterText(context, 'lunarMonth${month.clamp(1, 12)}');
  }
}

/// «جمعه» / «Friday» for a civil day.
String converterWeekdayName(BuildContext context, DateTime day) =>
    converterText(context, 'weekday${day.weekday}');

/// `1405/08/22`, in the reader's digits — what the date field holds.
String converterDateNumeric(BuildContext context, ConverterDate date) =>
    nexDigits(date.numeric, persian: converterIsPersian(context));

/// A number as this module writes every number.
String converterNumberText(
  BuildContext context,
  double value, {
  int? decimals,
}) => converterFormatNumber(
  value,
  persian: converterIsPersian(context),
  decimals: decimals,
);

/// A unit's name, with «(approx.)» when its value varied by place or era.
String converterUnitLabel(BuildContext context, ConverterUnit unit) {
  final name = converterText(context, 'unit_${unit.id}');
  return unit.approximate
      ? '$name${converterText(context, 'approxSuffix')}'
      : name;
}

/// A size as printed on a label, in the reader's digits.
String converterSizeText(BuildContext context, String label) =>
    converterShowSize(label, persian: converterIsPersian(context));

/// «۸۸ سانتیمتر» for a body measurement.
String converterMeasureText(BuildContext context, SizeMeasure measure) {
  final unit = measure.unit == SizeUnit.mm
      ? converterText(context, 'mmUnit')
      : converterText(context, 'cmUnit');
  final value = converterFormatNumber(
    measure.value,
    persian: converterIsPersian(context),
    decimals: measure.value == measure.value.roundToDouble() ? 0 : 1,
  );
  return '$value $unit';
}

/// The name of a measurement: «دور سینه», «طول پا».
///
/// The keys are written `bust`, `waist`, `hip`… and the words `measureBust`,
/// `measureWaist`, so one capital letter is all that is missing between them.
String converterMeasureName(BuildContext context, String key) =>
    converterText(context, 'measure${_capitalised(key)}');

String _capitalised(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
