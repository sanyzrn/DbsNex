import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'craving_list.dart';
import 'module.dart';
import 'money_format.dart';
import 'quit_model.dart';
import 'smoke_math.dart';

/// What the screen shows before the first attempt: an honest, small
/// invitation — not a questionnaire.
class NoAttempt extends StatelessWidget {
  const NoAttempt({
    super.key,
    required this.onStart,
    required this.past,
    required this.cravings,
  });

  final VoidCallback onStart;
  final List<QuitAttempt> past;
  final List<Craving> cravings;

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        NexSpacing.lg,
        NexSpacing.md,
        NexSpacing.lg + nexBottomInset(context),
      ),
      children: [
        NexEmptyState(
          icon: Icons.smoke_free_outlined,
          message: strings(context, 'noActive'),
          action: FilledButton.icon(
            key: const ValueKey('smoke-start'),
            onPressed: onStart,
            icon: const Icon(Icons.flag_outlined),
            label: Text(strings(context, 'startButton')),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(top: NexSpacing.md),
          child: Text(
            strings(context, 'explainBaseline'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (past.isNotEmpty) ...[
          const SizedBox(height: NexSpacing.md),
          AttemptHistory(attempts: past),
        ],
        const SizedBox(height: NexSpacing.sm),
        Text(
          strings(context, 'estimateBoundary'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: NexSpacing.lg),
        CravingList(cravings: cravings),
      ],
    );
  }
}

/// The running dashboard.
class SmokeDashboard extends StatelessWidget {
  const SmokeDashboard({
    super.key,
    required this.attempt,
    required this.past,
    required this.cravings,
    required this.onLapse,
  });

  final QuitAttempt attempt;
  final List<QuitAttempt> past;
  final List<Craving> cravings;
  final VoidCallback onLapse;

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final persian = NexModuleStrings.persian(context);
    final now = DateTime.now();
    final progress = SmokeMath.progress(attempt, now);

    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        NexSpacing.lg + nexBottomInset(context),
      ),
      children: [
        NexPanel(
          icon: Icons.timelapse_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings(
                  context,
                  progress.days == 0 ? 'smokeFreeToday' : 'smokeFreeFor',
                  {'days': progress.days},
                ),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: NexSpacing.xs),
              Text(
                strings(context, supportMessageKey(progress.days)),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        NexPanel(
          title: strings(context, 'title'),
          icon: Icons.savings_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EstimateLine(
                icon: Icons.smoke_free_outlined,
                text: strings(context, 'cigarettesAvoided', {
                  'n': progress.cigarettesAvoided,
                }),
              ),
              const SizedBox(height: NexSpacing.sm),
              _EstimateLine(
                icon: Icons.account_balance_wallet_outlined,
                text: strings(context, 'moneySaved', {
                  'money': formatExactMoney(
                    progress.moneySavedMinor,
                    attempt.currency,
                    attempt.digits,
                    persian,
                  ),
                }),
              ),
              const SizedBox(height: NexSpacing.md),
              Text(
                strings(context, 'estimateNote', {
                  'perDay': attempt.cigarettesPerDay,
                  'price': formatMoney(
                    attempt.pricePerPackMinor,
                    attempt.currency,
                    attempt.digits,
                    persian,
                  ),
                  'perPack': attempt.perPack,
                }),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (past.isNotEmpty) ...[
          const SizedBox(height: NexSpacing.md),
          AttemptHistory(attempts: past),
        ],
        const SizedBox(height: NexSpacing.sm),
        Text(
          strings(context, 'estimateBoundary'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: NexSpacing.lg),
        CravingList(cravings: cravings),
        const SizedBox(height: NexSpacing.xl),
      ],
    );
  }
}

class _EstimateLine extends StatelessWidget {
  const _EstimateLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: NexSpacing.sm),
        Expanded(child: Text(text, style: theme.textTheme.titleSmall)),
      ],
    );
  }
}

class AttemptHistory extends StatelessWidget {
  const AttemptHistory({super.key, required this.attempts});
  final List<QuitAttempt> attempts;
  @override
  Widget build(BuildContext context) => NexPanel(
    title: smokeFreeStrings(context, 'historyHeading'),
    icon: Icons.history_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final attempt in attempts)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: NexSpacing.xs,
            ),
            child: Text(
              smokeFreeStrings(
                context,
                SmokeMath.attemptSpanDays(attempt) == 0
                    ? 'attemptSameDay'
                    : 'attemptLine',
                {'days': SmokeMath.attemptSpanDays(attempt)},
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    ),
  );
}
