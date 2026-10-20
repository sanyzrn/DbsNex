import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'occasion_math.dart';
import 'occasion_model.dart';
import 'occasion_text.dart';

/// One occasion in the list: what it is, which day it next falls on in its
/// own calendar, how old it comes to, and how far away it is.
class OccasionRow extends StatelessWidget {
  const OccasionRow({
    super.key,
    required this.index,
    required this.count,
    required this.occasion,
    required this.next,
    required this.today,
    required this.onOpen,
  });

  final int index;
  final int count;
  final Occasion occasion;

  /// The next time it falls; null for a date that cannot be worked out.
  final OccasionDay? next;
  final DateTime today;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = occasionsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final day = next;
    final days = day == null ? null : daysUntil(today, day.date);
    final years = day == null ? null : yearsText(context, occasion, day);
    final subtitle = [
      if (day != null)
        occasionDateText(
          context,
          day.date,
          solar: occasion.calendar == OccasionCalendar.jalali,
        )
      else
        strings(context, 'fixDate'),
      ?years,
      if (occasion.muted) strings(context, 'muted'),
    ].join(' · ');
    final title = occasion.title.isEmpty
        ? strings(context, 'untitled')
        : occasion.title;
    return NexGroupedRow(
      index: index,
      count: count,
      child: InkWell(
        key: ValueKey('occasion-${occasion.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.md,
          ),
          child: Row(
            children: [
              NexIconTile(
                occasionIcon(occasion.kind),
                color: NexHue.rose.of(theme.brightness),
              ),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: occasion.muted
                                  ? scheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                        ),
                        if (occasion.favorite) ...[
                          const SizedBox(width: NexSpacing.xs),
                          Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: scheme.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: NexSpacing.xs),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (days != null) ...[
                const SizedBox(width: NexSpacing.sm),
                Text(
                  countdownText(context, days),
                  key: ValueKey('occasion-days-${occasion.id}'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: days == 0 ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: days == 0 ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
