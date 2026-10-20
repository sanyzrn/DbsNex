import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'money_format.dart';
import 'quit_habits.dart';
import 'quit_model.dart';
import 'quit_widgets.dart';
import 'setup_sheet.dart';
import 'smoke_free_screen.dart';
import 'smoke_math.dart';
import 'store_state.dart';

/// Quit Habits: everything the person is quitting, each with its own count.
/// Opening one is its own page; adding one starts with what it is.
class QuitHomeScreen extends StatefulWidget {
  const QuitHomeScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<QuitHomeScreen> createState() => _QuitHomeScreenState();
}

class _QuitHomeScreenState extends State<QuitHomeScreen>
    with WidgetsBindingObserver, StoreState<QuitHomeScreen> {
  List<QuitAttempt> _attempts = const [];
  StreamSubscription<void>? _changes;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load() => readRecords(() async {
    final quits = await widget.store.list('quit');
    if (!mounted) return;
    setState(() => _attempts = quits.map(QuitAttempt.fromRecord).toList());
  });

  Future<void> _add() async {
    if (_adding) return;
    _adding = true;
    try {
      await showSetupSheet(context, widget.store, choose: true);
    } finally {
      _adding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final habits = quitHabitsOf(_attempts);
    final running = habits.where((a) => a.isActive).toList();
    final ended = habits.where((a) => !a.isActive).toList();
    return Scaffold(
      appBar: NexAppBar(title: Text(strings(context, 'title'))),
      // One primary action per page: with no habit yet it is the button in
      // the empty state.
      floatingActionButton: habits.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('quit-add'),
              onPressed: () => unawaited(_add()),
              icon: const Icon(Icons.add),
              label: Text(strings(context, 'addHabit')),
            ),
      body: recordsBody(
        habits.isEmpty
            ? ListView(
                padding: const EdgeInsetsDirectional.all(NexSpacing.md),
                children: [
                  NexEmptyState(
                    icon: Icons.self_improvement_outlined,
                    message: strings(context, 'homeEmpty'),
                    action: FilledButton.icon(
                      key: const ValueKey('quit-add'),
                      onPressed: () => unawaited(_add()),
                      icon: const Icon(Icons.add),
                      label: Text(strings(context, 'addHabit')),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.xl * 3 + nexBottomInset(context),
                ),
                children: [
                  if (running.isNotEmpty) ...[
                    NexShelfHeading(
                      icon: Icons.self_improvement_outlined,
                      title: strings(context, 'activeHeading'),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    for (final (i, a) in running.indexed)
                      NexGroupedRow(
                        index: i,
                        count: running.length,
                        child: _HabitTile(attempt: a, store: widget.store),
                      ),
                  ],
                  if (ended.isNotEmpty) ...[
                    const SizedBox(height: NexSpacing.lg),
                    NexShelfHeading(
                      icon: Icons.history_outlined,
                      title: strings(context, 'endedHeading'),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    for (final (i, a) in ended.indexed)
                      NexGroupedRow(
                        index: i,
                        count: ended.length,
                        child: _HabitTile(attempt: a, store: widget.store),
                      ),
                  ],
                ],
              ),
        () => unawaited(_load()),
      ),
    );
  }
}

class _HabitTile extends StatelessWidget {
  const _HabitTile({required this.attempt, required this.store});

  final QuitAttempt attempt;
  final NexModuleStore store;

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final progress = SmokeMath.progress(attempt, DateTime.now());
    final preset = quitPresetOf(attempt.habit);
    final started = !attempt.startedAt.isAfter(DateTime.now());
    final subtitle = [
      if (!started)
        strings(context, 'startsIn', {
          'n': SmokeMath.elapsedDays(DateTime.now(), attempt.startedAt),
        })
      else
        strings(
          context,
          progress.days == 0
              ? 'todayWithout'
              : progress.days == 1
              ? 'oneDayWithout'
              : 'daysWithout',
          {'days': progress.days, 'habit': quitWithout(context, attempt)},
        ),
      if (attempt.pricePerPackMinor > 0 &&
          progress.moneySavedMinor > BigInt.zero)
        strings(context, 'moneySaved', {
          'money': formatExactMoney(
            progress.moneySavedMinor,
            attempt.currency,
            attempt.digits,
            persian,
          ),
        }),
    ];
    return ListTile(
      key: ValueKey('quit-habit-${attempt.key}'),
      leading: Icon(preset.icon, color: scheme.primary),
      title: Text(
        quitHabitLabel(context, attempt),
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        subtitle.join('\n'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      isThreeLine: subtitle.length > 1,
      trailing: attempt.isActive
          ? null
          : Icon(Icons.history_outlined, color: scheme.onSurfaceVariant),
      onTap: () => unawaited(
        Navigator.push(
          context,
          NexPageRoute<void>(
            builder: (_) => SmokeFreeScreen(store: store, habit: attempt.key),
          ),
        ),
      ),
    );
  }
}
