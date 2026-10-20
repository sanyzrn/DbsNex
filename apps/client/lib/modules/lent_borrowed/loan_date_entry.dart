import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_dates.dart';
import 'loan_model.dart';
import 'number_input.dart';

/// Absolute date entry, on the calendar the app is set to. The field holds
/// `yyyy/MM/dd`, the shared calendar button beside it lets a person pick a
/// day (Jalali for a Persian reader on the solar calendar), and storage keeps
/// the local civil `YYYY-MM-DD` key.
///
/// Typed entry accepts `/`, `-` or `.` separators, one- or two-digit month
/// and day, and Latin, Persian or Arabic digits. Impossible dates are
/// refused, never normalized to a different day; years outside 1900–2100 —
/// the calendar's own range — are refused too, so a Persian year such as
/// 1405 is never silently stored as the civil year 1405.
String? parseDateEntry(String raw) {
  final match = RegExp(
    r'^(\d{4})[/.\-](\d{1,2})[/.\-](\d{1,2})$',
  ).firstMatch(normalizeNumber(raw.trim()));
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (year < 1900 || year > 2100) return null;
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return civilDateKey(date);
}

/// The civil key as the field shows it, `yyyy/MM/dd`.
String dateEntryText(String key) => key.replaceAll('-', '/');

/// The civil key as the shared module-date label — Jalali with Persian
/// digits for a solar-calendar reader, the civil date otherwise. Built as a
/// local date: a UTC midnight would read as the day before on a device
/// west of Greenwich.
String loanDateLabel(BuildContext context, String key) {
  final date = parseCivilDate(key);
  if (date == null) return key;
  return nexModuleDateLabel(context, DateTime(date.year, date.month, date.day));
}
