import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'archive_screen.dart';
import 'habit_detail_screen.dart';
import 'habit_edit_sheet.dart';
import 'habit_log.dart';
import 'habit_math.dart';
import 'habit_model.dart';
import 'habit_row.dart';
import 'habit_visuals.dart';
import 'module.dart';
import 'record_bundle.dart';
import 'store_state.dart';
import 'week_settings.dart';

/// The Habits module's Today screen (2.4.0): the day as a ring of every
/// habit due today, then what is still to do, what is done, and the habits
/// resting today. A tap on a habit's mark keeps it — or adds one to its
/// amount; a tap on its words opens its page.
class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen>
    with WidgetsBindingObserver, StoreState<HabitsScreen> {
  List<Habit> _habits = const [];
  List<HabitCheck> _checks = const [];
  StreamSubscription<void>? _changes;
  int _loadToken = 0;
  int _firstDay = DateTime.saturday;
  bool _showDone = true;
  bool _showResting = false;

  /// Habits whose write is still in flight, so a second tap does not race
  /// the first.
  final Set<String> _writing = {};

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

  /// Loads everything again. Only the newest call may land in `setState`:
  /// a slow earlier read arriving late must not overwrite fresher data.
  Future<void> _load() => readRecords(_read);

  Future<void> _read() async {
    await RecordBundle.recover(widget.store);
    final token = ++_loadToken;
    final habits = await widget.store.list('habit');
    final checks = await widget.store.list('check');
    final settings = await widget.store.get('settings', 'week');
    if (!mounted || token != _loadToken) return;
    setState(() {
      _habits = habits.map(Habit.fromRecord).toList()..sort(newestFirst);
      _checks = checks.map(HabitCheck.fromRecord).toList();
      _firstDay = readFirstDay(settings);
    });
  }

  Map<String, List<HabitCheck>> get _checksByHabit {
    final map = <String, List<HabitCheck>>{};
    for (final check in _checks) {
      map.putIfAbsent(check.habitId, () => []).add(check);
    }
    return map;
  }

  /// Runs one write for [habit], one at a time per habit.
  Future<void> _write(
    Habit habit,
    Future<void> Function(HabitLog log) write,
  ) async {
    if (_writing.contains(habit.id)) return;
    setState(() => _writing.add(habit.id));
    try {
      await write(HabitLog(widget.store, AppLocalizations.of(context)));
    } catch (_) {
      writeError();
    } finally {
      if (mounted) setState(() => _writing.remove(habit.id));
    }
  }

  /// The tap on a habit's mark. A tick is kept, or taken back with Undo —
  /// the one delete an accidental tap can cause, and Undo writes the exact
  /// record back. An amount goes up by one; once the day's goal is reached,
  /// the tap opens the amount sheet instead of adding past it by accident.
  Future<void> _mark(Habit habit, HabitStanding standing) async {
    if (habit.counted) {
      if (standing.todayDone) return _amount(habit, standing);
      return _write(
        habit,
        (log) => log.setAmount(
          habit,
          dateKeyOf(DateTime.now()),
          standing.todayAmount + 1,
        ),
      );
    }
    final messenger = ScaffoldMessenger.of(context);
    final undo = AppLocalizations.of(context).undo;
    final removed = habitsStrings(context, 'checkinDeleted');
    final failed = habitsStrings(context, 'saveError');
    await _write(habit, (log) async {
      final day = dateKeyOf(DateTime.now());
      final existing = await log.toggle(habit, day);
      if (existing == null) return;
      messenger.showSnackBar(SnackBar(
        content: Text(removed),
        action: SnackBarAction(label: undo,
        onPressed: () => unawaited(
          log
              .restore(habit, day, existing)
              .catchError(
                (Object _) =>
                    messenger.showSnackBar(SnackBar(content: Text(failed))),
              ),
        )),
      ));
    });
  }

  Future<void> _amount(Habit habit, HabitStanding standing) async {
    final value = await showHabitAmountSheet(
      context,
      habit: habit,
      current: standing.todayAmount,
    );
    if (value == null || value == standing.todayAmount || !mounted) return;
    await _write(
      habit,
      (log) => log.setAmount(habit, dateKeyOf(DateTime.now()), value),
    );
  }

  Future<void> _newHabit() =>
      showHabitEditSheet(context, widget.store, firstDay: _firstDay);

  void _open(Habit habit) => unawaited(
    Navigator.push(
      context,
      NexPageRoute<void>(
        builder: (_) =>
            HabitDetailScreen(store: widget.store, habitId: habit.id),
      ),
    ),
  );

  void _openArchive() => unawaited(
    Navigator.push(
      context,
      NexPageRoute<void>(builder: (_) => ArchiveScreen(store: widget.store)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final active = _habits.where((h) => !h.archived).toList();
    final byHabit = _checksByHabit;
    final now = DateTime.now();
    final rows = [
      for (final habit in active)
        (
          habit: habit,
          standing: HabitMath.fromChecks(
            habit,
            byHabit[habit.id] ?? const [],
            now,
            firstDay: _firstDay,
          ),
          logged: HabitMath.loggedDays(
            habit,
            byHabit[habit.id] ?? const [],
            now,
          ),
        ),
    ];
    bool dueNow(HabitStanding s, Habit h) =>
        s.dueToday && !(h.weekly && s.weekCount >= h.target);
    final todo = [
      for (final row in rows)
        if (!row.standing.todayDone && dueNow(row.standing, row.habit)) row,
    ];
    final done = [
      for (final row in rows)
        if (row.standing.todayDone) row,
    ];
    final resting = [
      for (final row in rows)
        if (!row.standing.todayDone && !dueNow(row.standing, row.habit)) row,
    ];
    final today = [...todo, ...done];

    Widget tile(
      ({Habit habit, HabitStanding standing, Map<DateTime, int> logged}) row,
    ) => HabitTile(
      key: ValueKey('habit-tile-${row.habit.id}'),
      habit: row.habit,
      standing: row.standing,
      logged: row.logged,
      firstDay: _firstDay,
      busy: _writing.contains(row.habit.id),
      onMark: () => unawaited(_mark(row.habit, row.standing)),
      onAmount: () => unawaited(_amount(row.habit, row.standing)),
      onOpen: () => _open(row.habit),
    );

    return Scaffold(
      appBar: NexAppBar(
        title: Text(strings(context, 'title')),
        actions: [
          IconButton(
            key: const ValueKey('habits-week-settings'),
            tooltip: strings(context, 'weekStart'),
            icon: const Icon(Icons.tune_outlined),
            onPressed: () =>
                unawaited(showWeekSettings(context, widget.store, _firstDay)),
          ),
          IconButton(
            key: const ValueKey('habits-archive'),
            tooltip: strings(context, 'archived'),
            icon: const Icon(Icons.archive_outlined),
            onPressed: _openArchive,
          ),
        ],
      ),
      // One primary action per page: with nothing yet, it is the button in
      // the empty state, not a second one floating beside it.
      floatingActionButton: _habits.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('habits-new'),
              onPressed: () => unawaited(_newHabit()),
              icon: const Icon(Icons.add),
              label: Text(strings(context, 'newHabit')),
            ),
      body: recordsBody(
        _habits.isEmpty
            ? ScrollSafeEmpty(
                child: NexEmptyState(
                  icon: Icons.event_repeat_outlined,
                  message: strings(context, 'empty'),
                  action: FilledButton.icon(
                    key: const ValueKey('habits-new'),
                    onPressed: () => unawaited(_newHabit()),
                    icon: const Icon(Icons.add),
                    label: Text(strings(context, 'newHabit')),
                  ),
                ),
              )
            : active.isEmpty
            ? ScrollSafeEmpty(
                child: NexEmptyState(
                  icon: Icons.archive_outlined,
                  message: strings(context, 'allArchived'),
                  action: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: () => unawaited(_newHabit()),
                        icon: const Icon(Icons.add),
                        label: Text(strings(context, 'newHabit')),
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      TextButton.icon(
                        key: const ValueKey('habits-open-archived'),
                        onPressed: _openArchive,
                        icon: const Icon(Icons.archive_outlined),
                        label: Text(strings(context, 'openArchived')),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.xl * 3 + nexBottomInset(context),
                ),
                children: [
                  HabitsDayCard(
                    key: const ValueKey('habits-hero'),
                    now: now,
                    pieces: [
                      for (final row in today)
                        (
                          color: Color.lerp(
                            habitHueOf(row.habit).base,
                            Colors.white,
                            0.25,
                          )!,
                          progress: row.habit.counted
                              ? row.standing.todayAmount / row.habit.goal
                              : row.standing.todayDone
                              ? 1.0
                              : 0.0,
                        ),
                    ],
                    done: done.length,
                    due: today.length,
                    resting: resting.length,
                    best: rows.isEmpty
                        ? null
                        : (rows.toList()..sort(
                                (a, b) => b.standing.streak.compareTo(
                                  a.standing.streak,
                                ),
                              ))
                              .first,
                  ),
                  const SizedBox(height: NexSpacing.lg),
                  if (todo.isNotEmpty) ...[
                    NexShelfHeading(
                      icon: Icons.radio_button_unchecked_rounded,
                      title: strings(context, 'toDo'),
                      note: strings(context, 'todaySummary', {
                        'done': done.length,
                        'total': today.length,
                      }),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    for (final row in todo) tile(row),
                  ],
                  if (done.isNotEmpty) ...[
                    const SizedBox(height: NexSpacing.sm),
                    _SectionToggle(
                      key: const ValueKey('habits-done-toggle'),
                      icon: Icons.check_circle_rounded,
                      title: strings(context, 'doneToday'),
                      count: done.length,
                      open: _showDone,
                      onTap: () => setState(() => _showDone = !_showDone),
                    ),
                    if (_showDone)
                      for (final row in done) tile(row),
                  ],
                  if (resting.isNotEmpty) ...[
                    const SizedBox(height: NexSpacing.sm),
                    _SectionToggle(
                      key: const ValueKey('habits-resting-toggle'),
                      icon: Icons.bedtime_outlined,
                      title: strings(context, 'notToday'),
                      count: resting.length,
                      open: _showResting,
                      onTap: () => setState(() => _showResting = !_showResting),
                    ),
                    if (_showResting)
                      for (final row in resting) tile(row),
                  ],
                ],
              ),
        () => unawaited(_load()),
      ),
    );
  }
}

/// The card at the top of Today, coloured by the hour — dawn, day, dusk,
/// night — with the day ring, how many are kept, and the longest streak
/// still going.
class HabitsDayCard extends StatelessWidget {
  const HabitsDayCard({
    super.key,
    required this.now,
    required this.pieces,
    required this.done,
    required this.due,
    required this.resting,
    required this.best,
  });

  final DateTime now;
  final List<HabitDayPiece> pieces;
  final int done;
  final int due;
  final int resting;
  final ({Habit habit, HabitStanding standing, Map<DateTime, int> logged})?
  best;

  static (Color, Color) _sky(int hour) => switch (hour) {
    >= 5 && < 11 => (const Color(0xFFB45309), const Color(0xFFBE123C)),
    >= 11 && < 17 => (const Color(0xFF0369A1), const Color(0xFF0F766E)),
    >= 17 && < 21 => (const Color(0xFF4338CA), const Color(0xFF7E22CE)),
    _ => (const Color(0xFF1E1B4B), const Color(0xFF3730A3)),
  };

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    const white = Colors.white;
    final (from, to) = _sky(now.hour);
    final left = due - done;
    final caption = due == 0
        ? strings(context, resting > 0 ? 'heroRest' : 'heroNone')
        : left == 0
        ? strings(context, 'heroAll')
        : left == 1
        ? strings(context, 'heroOneLeft')
        : strings(context, 'heroLeft', {'n': left});
    final best = this.best;
    final bestName = best == null
        ? ''
        : best.habit.name.isEmpty
        ? strings(context, 'untitled')
        : best.habit.name;
    return Semantics(
      container: true,
      label: strings(context, 'todaySummary', {'done': done, 'total': due}),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [from, to],
          ),
          borderRadius: BorderRadius.circular(NexRadius.xl),
          boxShadow: [
            BoxShadow(
              color: to.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Row(
            children: [
              HabitDayRing(
                pieces: pieces,
                size: 104,
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nexDigits('$done/$due', persian: persian),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        strings(context, 'today'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: NexSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nexModuleDateLabel(context, now),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: NexSpacing.xs),
                    Text(
                      caption,
                      key: const ValueKey('habits-hero-caption'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (best != null && best.standing.streak >= 2) ...[
                      const SizedBox(height: NexSpacing.sm),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(NexRadius.pill),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: NexSpacing.sm,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.local_fire_department_rounded,
                                size: 16,
                                color: white,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  strings(context, 'bestGoing', {
                                    'n': best.standing.streak,
                                    'name': bestName,
                                  }),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section's heading that folds it: its name, how many, and a chevron.
class _SectionToggle extends StatelessWidget {
  const _SectionToggle({
    super.key,
    required this.icon,
    required this.title,
    required this.count,
    required this.open,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NexRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: NexSpacing.sm),
              Flexible(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: NexSpacing.xs),
              Text(
                nexDigits('$count', persian: NexModuleStrings.persian(context)),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: NexMotion.of(context, NexMotion.standard),
                child: Icon(
                  Icons.expand_more_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}