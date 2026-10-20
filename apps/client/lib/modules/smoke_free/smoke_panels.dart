import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'craving_list.dart';
import 'module.dart';
import 'money_format.dart';
import 'quit_model.dart';
import 'quit_widgets.dart';
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
            // Material's default caps a filled button at 40 px tall,
            // which a 2× text scale cannot fit into; let it grow with the
            // words instead of clipping them.
            style: const ButtonStyle(
              maximumSize: WidgetStatePropertyAll<Size?>(
                Size(double.infinity, double.infinity),
              ),
            ),
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
    this.onHelp,
  });

  final QuitAttempt attempt;
  final List<QuitAttempt> past;
  final List<Craving> cravings;
  final VoidCallback onLapse;

  /// Opens the help sheet for a craving.
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final persian = NexModuleStrings.persian(context);
    final now = DateTime.now();
    final progress = SmokeMath.progress(attempt, now);

    final theme = Theme.of(context);
    final legacy = attempt.habit == defaultHabit;
    final habit = quitWithout(context, attempt);
    final started = !attempt.startedAt.isAfter(now);
    final units = progress.cigarettesAvoided;
    final money = progress.moneySavedMinor;
    final timeKept = units * attempt.minutesPerUnit;
    final goalPct = attempt.goalMinor > 0
        ? (money * BigInt.from(100) ~/ BigInt.from(attempt.goalMinor))
              .toInt()
              .clamp(0, 100)
        : null;

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
              if (started)
                Text(
                  legacy
                      ? strings(
                          context,
                          progress.days == 0
                              ? 'smokeFreeToday'
                              : progress.days == 1
                              ? 'smokeFreeOneDay'
                              : 'smokeFreeFor',
                          {'days': progress.days},
                        )
                      : strings(
                          context,
                          progress.days == 0
                              ? 'todayWithout'
                              : progress.days == 1
                              ? 'oneDayWithout'
                              : 'daysWithout',
                          {'days': progress.days, 'habit': habit},
                        ),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              LiveCounter(
                startedAt: attempt.startedAt,
                style: started
                    ? theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: NexSpacing.xs),
              Text(
                strings(context, supportMessageKey(progress.days)),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (onHelp != null) ...[
                const SizedBox(height: NexSpacing.md),
                FilledButton.tonalIcon(
                  key: const ValueKey('sos-open'),
                  onPressed: onHelp,
                  icon: const Icon(Icons.support_outlined),
                  label: Text(strings(context, 'sosButton')),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        NexPanel(
          title: quitHabitLabel(context, attempt),
          icon: Icons.savings_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EstimateLine(
                icon: Icons.smoke_free_outlined,
                text: legacy
                    ? strings(
                        context,
                        units == 1
                            ? 'cigarettesAvoidedOne'
                            : 'cigarettesAvoided',
                        {'n': units},
                      )
                    : strings(
                        context,
                        units == 1 ? 'unitsAvoidedOne' : 'unitsAvoided',
                        {'n': units, 'unit': quitUnit(context, attempt)},
                      ),
              ),
              if (attempt.pricePerPackMinor > 0) ...[
                const SizedBox(height: NexSpacing.sm),
                _EstimateLine(
                  icon: Icons.account_balance_wallet_outlined,
                  text: strings(context, 'moneySaved', {
                    'money': formatExactMoney(
                      money,
                      attempt.currency,
                      attempt.digits,
                      persian,
                    ),
                  }),
                ),
              ],
              if (timeKept > 0) ...[
                const SizedBox(height: NexSpacing.sm),
                _EstimateLine(
                  icon: Icons.schedule_outlined,
                  text: strings(context, 'timeKept', {
                    'time': quitDuration(context, timeKept),
                  }),
                ),
              ],
              if (goalPct != null) ...[
                const SizedBox(height: NexSpacing.md),
                Text(
                  strings(context, 'goalProgress', {
                    'pct': goalPct,
                    'goal': formatMoney(
                      attempt.goalMinor,
                      attempt.currency,
                      attempt.digits,
                      persian,
                    ),
                  }),
                  key: const ValueKey('quit-goal'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: NexSpacing.xs),
                LinearProgressIndicator(value: goalPct / 100),
              ],
              const SizedBox(height: NexSpacing.md),
              Text(
                legacy
                    ? strings(context, 'estimateNote', {
                        'perDay': attempt.cigarettesPerDay,
                        'price': formatMoney(
                          attempt.pricePerPackMinor,
                          attempt.currency,
                          attempt.digits,
                          persian,
                        ),
                        'perPack': attempt.perPack,
                      })
                    : strings(context, 'estimateUnits', {
                        'perDay': attempt.cigarettesPerDay,
                        'unit': quitUnit(context, attempt),
                        'price': formatMoney(
                          attempt.pricePerPackMinor,
                          attempt.currency,
                          attempt.digits,
                          persian,
                        ),
                      }),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (attempt.why.trim().isNotEmpty) ...[
          const SizedBox(height: NexSpacing.md),
          NexPanel(
            key: const ValueKey('quit-why'),
            title: strings(context, 'whyHeading'),
            icon: Icons.favorite_border,
            child: NexTextDirection(
              text: attempt.why,
              child: Text(attempt.why, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
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
        const SizedBox(height: NexSpacing.lg),
        QuitMarks(days: progress.days),
        const SizedBox(height: NexSpacing.md),
        QuitWeeks(attempt: attempt, cravings: cravings, past: past),
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
              _attemptText(context, attempt),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    ),
  );

  /// The honest span line for a past attempt: same-day attempts are said
  /// out loud, one-day attempts read in the singular, the rest keep their
  /// own count.
  static String _attemptText(BuildContext context, QuitAttempt attempt) {
    final span = SmokeMath.attemptSpanDays(attempt);
    return smokeFreeStrings(
      context,
      span == 0
          ? 'attemptSameDay'
          : span == 1
          ? 'attemptOneDay'
          : 'attemptLine',
      {'days': span},
    );
  }
}
