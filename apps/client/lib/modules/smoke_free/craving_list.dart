import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'craving_sheet.dart';
import 'module.dart';
import 'quit_model.dart';
import 'smoke_math.dart';

/// The cravings, grouped by honest relative day, with the pattern behind
/// them said in one line. Tapping a craving opens it for editing or
/// deletion — its own record, nothing else touched.
class CravingList extends StatelessWidget {
  const CravingList({super.key, required this.cravings, this.onChanged});

  final List<Craving> cravings;

  /// Notified after this list changed the store itself (delete + undo);
  /// the screen's own listener covers the rest.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    // A window, not the whole history: the newest thirty cravings the person
    // actually wants to glance at.
    final shown = cravings.take(30).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NexShelfHeading(
          icon: Icons.psychology_outlined,
          title: strings(context, 'cravingsHeading'),
        ),
        const SizedBox(height: NexSpacing.sm),
        if (cravings.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.all(NexSpacing.md),
            child: Text(
              strings(context, 'noCravings'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          _PatternLine(cravings: cravings),
          const SizedBox(height: NexSpacing.sm),
          for (final (index, craving) in shown.indexed)
            NexGroupedRow(
              index: index,
              count: shown.length,
              child: ListTile(
                onTap: () => _open(context, craving),
                title: Text(
                  _summary(context, craving),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  _dayLabel(context, craving, now),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                leading: Icon(
                  Icons.waves_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }

  String _summary(BuildContext context, Craving craving) {
    final strings = smokeFreeStrings;
    final intensity = switch (craving.intensity) {
      1 => strings(context, 'intensityLow'),
      3 => strings(context, 'intensityHigh'),
      _ => strings(context, 'intensityMedium'),
    };
    final parts = [intensity];
    if (craving.triggers.isNotEmpty) {
      parts.add(triggerLabel(context, craving.triggers.first));
    }
    return parts.join(' · ');
  }

  String _dayLabel(BuildContext context, Craving craving, DateTime now) {
    final strings = smokeFreeStrings;
    final days = SmokeMath.cravingDayIndex(craving.at, now);
    if (days < 0) {
      return strings(context, days == -1 ? 'tomorrowWord' : 'futureDate', {
        'n': -days,
      });
    }
    if (days == 0) return strings(context, 'todayWord');
    if (days == 1) return strings(context, 'yesterdayWord');
    return strings(context, 'daysAgoWord', {'n': days});
  }

  void _open(BuildContext context, Craving craving) {
    // The sheet needs the module's store, which the list receives through
    // its owner; opening it here keeps one source of truth for editing.
    final store = StoreScope.of(context);
    showCravingSheet(context, store, editing: craving);
  }
}

/// The most common trigger, in one quiet line — a pattern, not a chart.
class _PatternLine extends StatelessWidget {
  const _PatternLine({required this.cravings});

  final List<Craving> cravings;

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final counts = SmokeMath.triggerCounts(cravings);
    if (counts.isEmpty || counts.first.value < 2) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: NexSpacing.xs),
        child: Text(
          strings(context, 'patternNone'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final top = counts.first;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: NexSpacing.xs),
      child: Text(
        strings(context, 'patternTop', {
          'name': triggerLabel(context, top.key),
          'n': top.value,
        }),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A tiny inherited widget so deep list rows can reach the module's store
/// without threading it through every constructor.
class StoreScope extends InheritedWidget {
  const StoreScope({super.key, required this.store, required super.child});

  final NexModuleStore store;

  static NexModuleStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.store;

  @override
  bool updateShouldNotify(StoreScope oldWidget) => oldWidget.store != store;
}
