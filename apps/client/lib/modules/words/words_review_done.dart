part of 'words_review_page.dart';

/// The done state: what happened, and a calm goodbye. No streaks, no
/// scores, no confetti.
class _DoneView extends StatelessWidget {
  const _DoneView({required this.answered, required this.total});

  final int answered;
  final int total;

  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.self_improvement_outlined,
                size: NexEmptyState.iconSize,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: NexSpacing.md),
              Text(
                answered == 1
                    ? strings(context, 'sessionDoneOne')
                    : strings(context, 'sessionDone', {'count': answered}),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: NexSpacing.sm),
              Text(
                strings(context, 'sessionDoneCalm'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: NexSpacing.lg),
              _ScheduleDisclosure(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ladder, in one paragraph, on the done screen — where a person has
/// a moment to read it.
class _ScheduleDisclosure extends StatefulWidget {
  @override
  State<_ScheduleDisclosure> createState() => _ScheduleDisclosureState();
}

class _ScheduleDisclosureState extends State<_ScheduleDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    final content = Column(
      children: [
        TextButton.icon(
          key: const ValueKey('words-schedule-how'),
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
          label: Text(strings(context, 'scheduleHow')),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
            child: Text(
              strings(context, 'scheduleHowBody'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
    if (MediaQuery.disableAnimationsOf(context)) return content;
    return AnimatedSize(
      duration: NexMotion.standard,
      curve: NexMotion.curve,
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}
