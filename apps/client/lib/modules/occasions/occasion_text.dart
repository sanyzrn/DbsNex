import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'occasion_math.dart';
import 'occasion_model.dart';

IconData occasionIcon(OccasionKind kind) => switch (kind) {
  OccasionKind.birthday => Icons.cake_outlined,
  OccasionKind.anniversary => Icons.favorite_border,
  OccasionKind.memorial => Icons.local_florist_outlined,
  OccasionKind.other => Icons.event_outlined,
};

String occasionKindLabel(BuildContext context, OccasionKind kind) =>
    occasionsStrings(context, switch (kind) {
      OccasionKind.birthday => 'kindBirthday',
      OccasionKind.anniversary => 'kindAnniversary',
      OccasionKind.memorial => 'kindMemorial',
      OccasionKind.other => 'kindOther',
    });

String occasionGreeting(BuildContext context, OccasionKind kind) =>
    occasionsStrings(context, switch (kind) {
      OccasionKind.birthday => 'greetBirthday',
      OccasionKind.anniversary => 'greetAnniversary',
      OccasionKind.memorial => 'greetMemorial',
      OccasionKind.other => 'greetOther',
    });

/// «15 Mehr 1406» / «7 October 2027» — a day written in the calendar
/// [solar] picks, month in words, digits in the reader's script.
String occasionDateText(
  BuildContext context,
  DateTime date, {
  required bool solar,
}) => nexReadableDate(
  date,
  solar: solar,
  persian: NexModuleStrings.persian(context),
);

String occasionTimeText(BuildContext context, int minutes) {
  String two(int v) => v.toString().padLeft(2, '0');
  return nexDigits(
    '${two(minutes ~/ 60)}:${two(minutes % 60)}',
    persian: NexModuleStrings.persian(context),
  );
}

/// «Today», «Tomorrow», «in 12 days».
String countdownText(BuildContext context, int days) => days <= 0
    ? occasionsStrings(context, 'today')
    : days == 1
    ? occasionsStrings(context, 'tomorrow')
    : occasionsStrings(context, 'inDays', {'n': days});

/// «turns 27» for a birthday, «year 5» for the others; null when the start
/// year is unknown.
String? yearsText(BuildContext context, Occasion occasion, OccasionDay day) {
  final years = yearsAt(occasion, day);
  if (years == null) return null;
  return occasionsStrings(
    context,
    occasion.kind == OccasionKind.birthday ? 'turns' : 'yearN',
    {'n': years},
  );
}

/// What the notification says. Names the occasion except for a remembrance,
/// which stays neutral on a lock screen.
String occasionNotificationBody(BuildContext context, Occasion occasion) {
  if (occasion.kind == OccasionKind.memorial || occasion.title.isEmpty) {
    return occasionsStrings(context, 'notifNeutral');
  }
  final days = occasion.remindDays ?? 0;
  return occasionsStrings(
    context,
    days == 0
        ? 'notifToday'
        : days == 1
        ? 'notifTomorrow'
        : 'notifDays',
    {'name': occasion.title, 'n': days},
  );
}
