import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'costs.dart';
import 'logic.dart';
import 'models.dart';
import 'strings.dart';
import 'units.dart';

/// The shared presentational pieces: the date labels, the rule rows
/// with their calm bars, the event rows, the group headings. Every
/// number arrives computed; every word comes from the strings.

/// "Today", "Yesterday", or "13 October" — calendar-relative, never a
/// Jalali claim (the API offers no Jalali formatter; see the README's
/// Platform requests).
String eventDateLabel(BuildContext context, DateTime date, DateTime now) {
  final s = maintenanceStrings;
  final persian = NexModuleStrings.persian(context);
  if (dayOf(date) == dayOf(now)) return s(context, 'today');
  if (dayOf(date) == dayOf(now).subtract(const Duration(days: 1))) {
    return s(context, 'yesterday');
  }
  final day = persian ? persianDigits('${date.day}') : '${date.day}';
  final month = s(context, 'month${date.month.clamp(1, 12)}');
  final withYear = date.year != now.year;
  final year = persian ? persianDigits('${date.year}') : '${date.year}';
  return withYear ? '$day $month $year' : '$day $month';
}

String fullDateLabel(BuildContext context, DateTime date) {
  final fa = NexModuleStrings.persian(context),
      month = maintenanceStrings(context, 'month${date.month}');
  final day = fa ? persianDigits('${date.day}') : '${date.day}',
      year = fa ? persianDigits('${date.year}') : '${date.year}';
  return '$day $month $year';
}

/// The unit word for a rule's metre.
String unitWordOf(BuildContext context, DistanceUnit unit) =>
    maintenanceStrings(context, unit == DistanceUnit.km ? 'unitKm' : 'unitMi');

/// One interval rule's standing, as a row: the task, the due fact,
/// the calm bar. Unknowns are said, never smoothed over.
class RuleRow extends StatelessWidget {
  const RuleRow({
    super.key,
    required this.standing,
    required this.now,
    required this.onTap,
    this.onLog,
  });
  final RuleStanding standing;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onLog;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context),
        s = maintenanceStrings,
        rule = standing.rule;
    final fa = NexModuleStrings.persian(context), due = standing.dueNow(now);
    final unit = s(
      context,
      rule.hours != null
          ? 'unitHours'
          : rule.meterUnit == DistanceUnit.mi
          ? 'unitMi'
          : 'unitKm',
    );
    final facts = <String>[];
    if (rule.hasTime) {
      if (standing.timeUnknown) {
        facts.add(s(context, 'noPurchaseDate'));
      } else if (standing.timeDue != null) {
        facts.add(
          s(context, standing.dueByTime(now) ? 'overdueSince' : 'dueOn', {
            'date': fullDateLabel(context, standing.timeDue!),
          }),
        );
      }
    }
    if (rule.hasUsage) {
      if (standing.nextDueMeter == null) {
        facts.add(s(context, 'usageBaselineUnknown'));
      } else if (standing.meterUnknown) {
        facts.add(
          s(
            context,
            rule.hours != null ? 'hoursDueUnknown' : 'distanceDueUnknown',
          ),
        );
      } else {
        facts.add(
          s(context, 'usageNext', {
            'meter': formatMeterValue(standing.nextDueMeter!, persian: fa),
            'unit': unit,
          }),
        );
      }
    }
    final status = facts.join(' · ');
    final progress = standing.usageProgress > standing.timeProgress(now)
        ? standing.usageProgress
        : standing.timeProgress(now);
    return Semantics(
      label: s(context, 'ruleSemantics', {'task': rule.task, 'status': status}),
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(rule.task, style: theme.textTheme.bodyLarge),
              const SizedBox(height: NexSpacing.xs),
              Text(
                status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: due
                      ? NexHue.amber.of(theme.brightness)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if ((rule.hasTime && !standing.timeUnknown) ||
                  (rule.hasUsage && !standing.meterUnknown)) ...[
                const SizedBox(height: NexSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(NexRadius.xs),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(
                      NexHue.amber.of(theme.brightness),
                    ),
                  ),
                ),
              ],
              if (rule.hasUsage && standing.currentMeter != null)
                Text(
                  s(context, 'nowAt', {
                    'meter': formatMeterValue(
                      standing.currentMeter!,
                      persian: fa,
                    ),
                    'unit': unit,
                  }),
                  style: theme.textTheme.bodySmall,
                ),
              if (standing.readingAt != null && rule.hasUsage)
                Text(
                  s(context, 'readingAsOf', {
                    'date': fullDateLabel(context, standing.readingAt!),
                  }),
                  style: theme.textTheme.bodySmall,
                ),
              if (standing.converted)
                Text(
                  s(context, 'convertedReading'),
                  style: theme.textTheme.bodySmall,
                ),
              if (standing.basisPurchase)
                Text(
                  s(context, 'sincePurchase'),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One logged service, in the timeline.
class EventRow extends StatelessWidget {
  const EventRow({
    super.key,
    required this.event,
    required this.now,
    required this.onTap,
  });

  final ServiceEvent event;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = maintenanceStrings;
    final persian = NexModuleStrings.persian(context);
    final subtitle = [
      serviceDateKnown(event)
          ? eventDateLabel(context, event.date, now)
          : s(context, 'dateUnavailable'),
      if (validEventMeter(event))
        s(context, 'meterAtService', {
          'meter': formatMeterValue(
            event.meter!,
            scale: event.meterScale,
            persian: persian,
          ),
          'unit': event.meterUnit == null
              ? s(context, 'unitHours')
              : unitWordOf(context, event.meterUnit!),
        }),
      if (event.provider?.isNotEmpty == true)
        s(context, 'providedBy', {'provider': event.provider!}),
    ].join(' · ');
    final cost = event.valid && event.cost != null && event.currency != null
        ? '${formatCostNumber(event.cost!, costExponentOf(event.currency), persian: persian)} ${event.currency}'
        : null;
    return Semantics(
      label: s(context, 'eventSemantics', {
        'task': event.task,
        'date': eventDateLabel(context, event.date, now),
      }),
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                event.valid ? event.task : s(context, 'incompleteRecord'),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: NexSpacing.xs),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (cost != null)
                Text(
                  cost,
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.titleMedium,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
