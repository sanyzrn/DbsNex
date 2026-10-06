import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import '../../l10n/app_localizations.dart';

/// The two colours «Cycle» draws with: a soft rose for a period and a calm
/// teal for the fertile window. Fixed rather than taken from the accent —
/// a calendar whose period days turn green with the theme is not one
/// anybody can read at a glance — and lifted a step in dark mode.
Color cyclePeriodColor(Brightness brightness) => brightness == Brightness.dark
    ? const Color(0xFFF28DA4)
    : const Color(0xFFD9506F);

Color cycleFertileColor(Brightness brightness) => brightness == Brightness.dark
    ? const Color(0xFF72D2BF)
    : const Color(0xFF2E9C88);

const _persianMonths = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];
const _persianMonthsLatin = [
  'Farvardin',
  'Ordibehesht',
  'Khordad',
  'Tir',
  'Mordad',
  'Shahrivar',
  'Mehr',
  'Aban',
  'Azar',
  'Dey',
  'Bahman',
  'Esfand',
];

bool cyclePersian(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa';

String cycleDigits(BuildContext context, Object value) =>
    nexDigits('$value', persian: cyclePersian(context));

/// "14 Mehr" / «۱۴ مهر», or the locale's short month and day.
String cycleDayMonth(
  BuildContext context,
  DateTime day, {
  required bool solar,
}) {
  final persian = cyclePersian(context);
  if (solar) {
    final p = nexPersianDate(day);
    final month = (persian ? _persianMonths : _persianMonthsLatin)[p.month - 1];
    return nexDigits('${p.day} $month', persian: persian);
  }
  return nexDigits(
    MaterialLocalizations.of(context).formatShortMonthDay(day),
    persian: persian,
  );
}

/// The month and year heading a calendar page.
String cycleMonthTitle(
  BuildContext context,
  DateTime anchor, {
  required bool solar,
}) {
  final persian = cyclePersian(context);
  if (solar) {
    final p = nexPersianDate(anchor);
    final month = (persian ? _persianMonths : _persianMonthsLatin)[p.month - 1];
    return nexDigits('$month ${p.year}', persian: persian);
  }
  return MaterialLocalizations.of(context).formatMonthYear(anchor);
}

String cycleFlowLabel(AppLocalizations l10n, CycleFlow? flow) => switch (flow) {
  null => l10n.cycleFlowNone,
  CycleFlow.spotting => l10n.cycleFlowSpotting,
  CycleFlow.light => l10n.cycleFlowLight,
  CycleFlow.medium => l10n.cycleFlowMedium,
  CycleFlow.heavy => l10n.cycleFlowHeavy,
};

String cycleMoodLabel(AppLocalizations l10n, CycleMood mood) => switch (mood) {
  CycleMood.low => l10n.cycleMoodLow,
  CycleMood.sensitive => l10n.cycleMoodSensitive,
  CycleMood.calm => l10n.cycleMoodCalm,
  CycleMood.good => l10n.cycleMoodGood,
  CycleMood.great => l10n.cycleMoodGreat,
};

IconData cycleMoodIcon(CycleMood mood) => switch (mood) {
  CycleMood.low => Icons.sentiment_very_dissatisfied_outlined,
  CycleMood.sensitive => Icons.sentiment_dissatisfied_outlined,
  CycleMood.calm => Icons.sentiment_neutral_outlined,
  CycleMood.good => Icons.sentiment_satisfied_outlined,
  CycleMood.great => Icons.sentiment_very_satisfied_outlined,
};

String cycleSymptomLabel(AppLocalizations l10n, CycleSymptom symptom) =>
    switch (symptom) {
      CycleSymptom.cramps => l10n.cycleSymptomCramps,
      CycleSymptom.headache => l10n.cycleSymptomHeadache,
      CycleSymptom.backPain => l10n.cycleSymptomBackPain,
      CycleSymptom.bloating => l10n.cycleSymptomBloating,
      CycleSymptom.breastTenderness => l10n.cycleSymptomBreastTenderness,
      CycleSymptom.acne => l10n.cycleSymptomAcne,
      CycleSymptom.nausea => l10n.cycleSymptomNausea,
      CycleSymptom.fatigue => l10n.cycleSymptomFatigue,
      CycleSymptom.cravings => l10n.cycleSymptomCravings,
      CycleSymptom.insomnia => l10n.cycleSymptomInsomnia,
      CycleSymptom.dizziness => l10n.cycleSymptomDizziness,
      CycleSymptom.discharge => l10n.cycleSymptomDischarge,
    };

String cycleAlertText(AppLocalizations l10n, CycleAlert alert) =>
    switch (alert) {
      CycleAlert.late => l10n.cycleAlertLate,
      CycleAlert.longPeriod => l10n.cycleAlertLongPeriod,
      CycleAlert.shortCycle => l10n.cycleAlertShortCycle,
      CycleAlert.longCycle => l10n.cycleAlertLongCycle,
      CycleAlert.irregular => l10n.cycleAlertIrregular,
    };

String cycleModeLabel(AppLocalizations l10n, CycleMode mode) => switch (mode) {
  CycleMode.normal => l10n.cycleModeNormal,
  CycleMode.conceive => l10n.cycleModeConceive,
  CycleMode.pregnant => l10n.cycleModePregnant,
  CycleMode.breastfeeding => l10n.cycleModeBreastfeeding,
  CycleMode.menopause => l10n.cycleModeMenopause,
};

String cycleModeHint(AppLocalizations l10n, CycleMode mode) => switch (mode) {
  CycleMode.normal => l10n.cycleModeNormalHint,
  CycleMode.conceive => l10n.cycleModeConceiveHint,
  CycleMode.pregnant => l10n.cycleModePregnantHint,
  CycleMode.breastfeeding || CycleMode.menopause => l10n.cycleModeOffHint,
};
