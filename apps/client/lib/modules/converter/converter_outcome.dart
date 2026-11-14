import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'converter_date.dart';
import 'converter_format.dart';
import 'converter_history.dart';
import 'converter_number.dart';
import 'converter_size_tables.dart';
import 'converter_sizes.dart';
import 'converter_units.dart';

/// What one conversion is, written out: the line on the hero, the small facts
/// under it, the words the copy button puts on the clipboard, and the fields
/// a record keeps so the screen can be put back exactly as it was.
///
/// One shape for all three tabs, so the screen has one hero, one copy button
/// and one recent list rather than three of each.
class ConverterOutcome {
  const ConverterOutcome({
    required this.eyebrow,
    required this.headline,
    required this.caption,
    required this.chips,
    required this.copyText,
    required this.label,
    required this.payload,
    this.note,
  });

  /// What the headline is: the calendar, the pair of units, the size chart.
  final String eyebrow;

  /// The answer, large.
  final String headline;

  /// The line under it — the weekday, the size that was picked, what one unit
  /// is worth.
  final String caption;
  final List<String> chips;

  /// A line under the hero that says something the result itself cannot: that
  /// a lunar date is calculated, that a traditional unit is approximate.
  final String? note;

  /// What a tap on Copy puts on the clipboard — all of it, not just the
  /// headline.
  final String copyText;

  /// One line for the recent list.
  final String label;

  /// Everything needed to put this conversion back in the fields.
  final Map<String, Object?> payload;
}

/// A day, in all three calendars.
ConverterOutcome? converterDatesOutcome(
  BuildContext context,
  ConverterDate day,
) {
  final civil = day.civilDay;
  if (civil == null) return null;
  final solar = day.inCalendar(ConverterCalendar.solar);
  final gregorian = day.inCalendar(ConverterCalendar.gregorian);
  final lunar = day.inCalendar(ConverterCalendar.lunar);
  if (solar == null || gregorian == null || lunar == null) return null;

  // The app's own calendar comes first, since that is the one the person
  // reads everything else in; the other two are the answer they came for.
  final main = NexModuleCalendar.solarOf(context) ? solar : gregorian;
  String nameOf(ConverterCalendar calendar) =>
      converterText(context, switch (calendar) {
        ConverterCalendar.solar => 'calSolar',
        ConverterCalendar.gregorian => 'calGregorian',
        ConverterCalendar.lunar => 'calLunar',
      });
  String shortOf(ConverterDate date) => converterText(
    context,
    switch (date.calendar) {
      ConverterCalendar.solar => 'solarShort',
      ConverterCalendar.gregorian => 'gregorianShort',
      ConverterCalendar.lunar => 'lunarShort',
    },
    {'date': converterDateLabel(context, date)},
  );

  final others = [
    for (final date in [solar, gregorian, lunar])
      if (date != main) date,
  ];
  final label = switch (day.calendar) {
    ConverterCalendar.lunar => '${shortOf(lunar)} = ${shortOf(solar)}',
    _ => '${shortOf(solar)} = ${shortOf(gregorian)}',
  };
  return ConverterOutcome(
    eyebrow: nameOf(main.calendar),
    headline: converterDateLabel(context, main),
    caption: converterWeekdayName(context, civil),
    chips: [for (final date in others) shortOf(date)],
    copyText: [
      '${nameOf(ConverterCalendar.solar)}: '
          '${converterDateLabel(context, solar)}',
      '${nameOf(ConverterCalendar.gregorian)}: '
          '${converterDateLabel(context, gregorian)}',
      '${nameOf(ConverterCalendar.lunar)}: '
          '${converterDateLabel(context, lunar)}',
    ].join('\n'),
    label: label,
    payload: {
      'cal': day.calendar.name,
      'y': day.year,
      'm': day.month,
      'd': day.day,
    },
    note: converterText(context, 'lunarNote'),
  );
}

/// A number of one unit, in another.
ConverterOutcome? converterUnitsOutcome(
  BuildContext context, {
  required UnitCategory category,
  required String fromId,
  required String toId,
  required String rawValue,
}) {
  final value = converterParseNumber(rawValue);
  if (value == null) return null;
  final from = converterUnitById(fromId);
  final to = converterUnitById(toId);
  if (from == null ||
      to == null ||
      from.category != category ||
      to.category != category) {
    return null;
  }
  final result = converterConvertUnit(
    category: category,
    fromId: fromId,
    toId: toId,
    value: value,
  );
  if (result == null || !result.isFinite) return null;
  final one = converterConvertUnit(
    category: category,
    fromId: fromId,
    toId: toId,
    value: 1,
  );
  final fromLabel = converterUnitLabel(context, from);
  final toLabel = converterUnitLabel(context, to);
  final fromAfter = converterUnitAfterNumber(context, from);
  final toAfter = converterUnitAfterNumber(context, to);
  final inputText = '${converterNumberText(context, value)} $fromAfter';
  final answer = '${converterNumberText(context, result)} $toAfter';
  final note = converterUnderAbsoluteZero(fromId, value)
      ? converterText(context, 'underAbsoluteZero')
      : from.noteKey != null
      ? converterText(context, from.noteKey!)
      : to.noteKey != null
      ? converterText(context, to.noteKey!)
      : converterUnitById(toId)?.approximate == true
      ? converterText(context, 'approxSuffix').trim()
      : null;
  return ConverterOutcome(
    eyebrow: '$fromLabel → $toLabel',
    headline: answer,
    caption: converterText(context, 'unitBaseLine', {
      'from': fromAfter,
      'factor': converterNumberText(context, one ?? 0),
      'to': toAfter,
    }),
    chips: const [],
    copyText: '$inputText = $answer',
    label: '$inputText = $answer',
    payload: {
      'cat': category.name,
      'from': fromId,
      'to': toId,
      'value': rawValue,
    },
    note: note,
  );
}

/// One size, in every system the chart knows, with the measurement it stands
/// for.
ConverterOutcome? converterSizesOutcome(
  BuildContext context,
  SizeChart chart,
  SizeSystem system,
  int rowIndex,
) {
  if (rowIndex < 0 || rowIndex >= chart.rows.length) return null;
  final row = chart.rows[rowIndex];
  final size = row.sizeIn(system.id);
  if (size == null) return null;
  final title = converterText(context, chart.titleKey);
  final first = row.measures.isEmpty ? null : row.measures.first;
  final others = [
    for (final other in chart.systems)
      if (other.id != system.id)
        '${converterText(context, other.labelKey)} '
            '${converterSizeText(context, row.sizeIn(other.id) ?? '—')}',
  ];
  final caption =
      '${converterText(context, system.labelKey)} '
      '${converterSizeText(context, size)}';
  return ConverterOutcome(
    eyebrow: title,
    headline: first == null
        ? converterSizeText(context, size)
        : converterMeasureText(context, first),
    caption: caption,
    chips: others,
    copyText: [
      title,
      for (final entry in chart.systems)
        '${converterText(context, entry.labelKey)}: '
            '${converterSizeText(context, row.sizeIn(entry.id) ?? '—')}',
      for (final measure in row.measures)
        '${converterMeasureName(context, measure.key)}: '
            '${converterMeasureText(context, measure)}',
    ].join('\n'),
    label: others.isEmpty
        ? '$title · $caption'
        : '$title · $caption = ${others.first}',
    payload: {'chart': chart.id, 'sys': system.id, 'row': rowIndex},
    note: chart.noteKey == null ? null : converterText(context, chart.noteKey!),
  );
}

/// The outcome a stored conversion describes, in today's language — what the
/// recent list shows and what tapping one puts back.
ConverterOutcome? converterOutcomeFromEntry(
  BuildContext context,
  ConverterEntry entry,
) {
  final payload = entry.payload;
  switch (entry.tab) {
    case ConverterTab.dates:
      final calendar = ConverterCalendar.values.firstWhere(
        (value) => value.name == payload['cal'],
        orElse: () => ConverterCalendar.solar,
      );
      final year = _intOf(payload['y']);
      final month = _intOf(payload['m']);
      final day = _intOf(payload['d']);
      if (year == null || month == null || day == null) return null;
      final date = ConverterDate(calendar, year, month, day);
      if (date.civilDay == null) return null;
      return converterDatesOutcome(context, date);
    case ConverterTab.units:
      final category = UnitCategory.values.firstWhere(
        (value) => value.name == payload['cat'],
        orElse: () => UnitCategory.length,
      );
      final from = payload['from'];
      final to = payload['to'];
      final raw = payload['value'];
      if (from is! String || to is! String || raw is! String) return null;
      return converterUnitsOutcome(
        context,
        category: category,
        fromId: from,
        toId: to,
        rawValue: raw,
      );
    case ConverterTab.sizes:
      final chartId = payload['chart'];
      final chart = converterSizeChartById(chartId is String ? chartId : '');
      if (chart == null) return null;
      final system = _systemOf(chart, payload['sys']);
      if (system == null) return null;
      return converterSizesOutcome(
        context,
        chart,
        system,
        _intOf(payload['row']) ?? -1,
      );
  }
}

SizeSystem? _systemOf(SizeChart chart, Object? id) {
  for (final system in chart.systems) {
    if (system.id == id) return system;
  }
  return null;
}

int? _intOf(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(converterLatinDigits(text)),
  _ => null,
};
