import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'quit_model.dart';
import 'quit_review_math.dart';
import 'smoke_math.dart';

class QuitInsightPanel extends StatelessWidget {
  const QuitInsightPanel({super.key, required this.cravings});
  final List<Craving> cravings;
  @override
  Widget build(BuildContext context) {
    final data = QuitInsights(cravings, DateTime.now());
    final theme = Theme.of(context);
    final counts = SmokeMath.triggerCounts(data.recent);
    return NexPanel(
      title: smokeFreeStrings(context, 'insightsTitle'),
      icon: Icons.insights_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              for (final pair in [
                (data.recent.length, 'insightLogs'),
                (data.rated, 'insightRated'),
                (data.eased, 'insightEased'),
              ])
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(NexRadius.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(NexSpacing.sm),
                    child: Text(
                      smokeFreeStrings(context, pair.$2, {'n': pair.$1}),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            data.recent.isEmpty
                ? smokeFreeStrings(context, 'insightsEmpty')
                : counts.isEmpty
                // Reports can exist without a trigger chosen. Saying “no
                // reports” then would be false; the pattern is simply
                // unknown.
                ? smokeFreeStrings(context, 'insightNoTrigger')
                : smokeFreeStrings(context, 'insightTrigger', {
                    'trigger': smokeFreeStrings(
                      context,
                      'trigger_${counts.first.key}',
                    ),
                    'n': counts.first.value,
                  }),
            style: theme.textTheme.bodyMedium,
          ),
          if (data.peakPeriod != null) ...[
            const SizedBox(height: NexSpacing.xs),
            Text(
              smokeFreeStrings(context, 'insightTime', {
                'period': smokeFreeStrings(
                  context,
                  'period_${data.peakPeriod}',
                ),
                'n': data.peakPeriodCount,
              }),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: NexSpacing.xs),
          Text(
            smokeFreeStrings(context, 'insightNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
