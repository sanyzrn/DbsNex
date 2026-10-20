import 'package:flutter/material.dart';

import 'loan_math.dart';
import 'module.dart';

/// How a due date reads today, in honest words — overdue said plainly, and
/// never "1 days". One wording for the list row and the detail panel.
String dueWording(BuildContext context, DueReading due) {
  final strings = lentStrings;
  return switch (due.status) {
    DueStatus.settled => strings(context, 'settledWord'),
    DueStatus.none => strings(context, 'noDueWord'),
    DueStatus.today => strings(context, 'dueTodayWord'),
    DueStatus.dueSoon =>
      due.days == 1
          ? strings(context, 'dueIn1')
          : strings(context, 'dueIn', {'n': due.days}),
    DueStatus.later => strings(context, 'dueIn', {'n': due.days}),
    DueStatus.overdue =>
      due.days == 1
          ? strings(context, 'overdueBy1')
          : strings(context, 'overdueBy', {'n': due.days}),
  };
}
