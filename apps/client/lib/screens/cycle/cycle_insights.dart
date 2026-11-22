import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import 'cycle_format.dart';
import 'cycle_space.dart';

/// The last few cycle lengths, drawn as bars.
///
/// The averages above it are the answer; this is the working. A cycle that
/// has been 28 days for months and then jumps to 35 is worth seeing before a
/// doctor does, and a run of bars says that in less space — and with less
/// arithmetic asked of the reader — than six numbers would. Oldest first, so
/// the reading direction alone puts the newest where the eye finishes.
class CycleLengthBars extends StatelessWidget {
  const CycleLengthBars({super.key, required this.lengths});

  /// Cycle lengths in days, oldest first. Fewer than two draws nothing:
  /// one bar is not a trend.
  final List<int> lengths;

  @override
  Widget build(BuildContext context) {
    if (lengths.length < 2) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final rose = cyclePeriodColor(theme.brightness);
    final longest = lengths.reduce(math.max);
    // A floor at a textbook cycle keeps two close lengths from being drawn
    // as a mountain range; the bar shows the length, not the difference.
    final scale = math.max(longest, 35);
    // With their unit: "28 days" reads as a length, "28" as a number.
    final values = lengths
        .map((d) => cycleDigits(context, l10n.cycleDays(d)))
        .join(cyclePersian(context) ? '، ' : ', ');
    return Semantics(
      label: '${l10n.cycleLengthHistory}: $values',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, size: 16, color: rose),
              const SizedBox(width: NexSpacing.xs),
              Expanded(
                child: Text(
                  l10n.cycleLengthHistory,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          SizedBox(
            // Room for a two-digit label and the tallest bar: a bar chart
            // that clips its own numbers is worse than no chart.
            height: 68,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, days) in lengths.indexed) ...[
                  if (i > 0) const SizedBox(width: NexSpacing.xs),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            cycleDigits(context, days),
                            // The chart is a picture of numbers; the
                            // semantics line above reads them at every text
                            // size, and scaling the labels here would only
                            // squeeze the bars they belong to.
                            textScaler: TextScaler.noScaling,
                            maxLines: 1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: i == lengths.length - 1
                                  ? rose
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: i == lengths.length - 1
                                  ? FontWeight.w700
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          height: 12 + 32 * (days / scale),
                          width: 14,
                          decoration: BoxDecoration(
                            color: i == lengths.length - 1
                                ? null
                                : rose.withValues(alpha: dark ? 0.34 : 0.26),
                            gradient: i == lengths.length - 1
                                ? cycleBloom(theme.brightness)
                                : null,
                            borderRadius: BorderRadius.circular(NexRadius.sm),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
