/// Gold Check's dates, on the person's own calendar.
///
/// Storage stays civil ISO (`YYYY-MM-DD`, the store's rule); what changed is
/// what a person reads. Every day the module shows goes through the shared
/// module date label, so a Persian reader on the Solar Hijri calendar sees a
/// Jalali day in Persian digits, and an English reader sees the civil day —
/// from the same stored value. A stored day that predates validation or
/// escaped it shows its stored text rather than a silently wrong date.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_format.dart';

/// A stored civil day as the person reads it, in their calendar and digits.
String goldStoredDateLabel(BuildContext context, String isoDate) {
  final text = normalizeGoldDate(isoDate);
  final day = DateTime.tryParse(text);
  return day == null
      ? goldDigits(text, NexModuleStrings.persian(context))
      : nexModuleDateLabel(context, day);
}
