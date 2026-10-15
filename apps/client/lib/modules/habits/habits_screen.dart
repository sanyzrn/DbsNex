import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'archive_screen.dart';
import 'habit_detail_screen.dart';
import 'habit_edit_sheet.dart';
import 'habit_model.dart';
import 'module.dart';
import 'store_state.dart';
import 'record_bundle.dart';
import 'habit_row.dart';
import 'week_settings.dart';

/// The Habits module's Today screen: every active habit with a one-tap
/// check-in, and the day's progress in one quiet line. Tapping a row's mark
/// toggles today's check-in; tapping the words opens the habit's detail
/// page, where the whole history lives.
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
      _habits = habits.map(Habit.fromRecord).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _checks = checks.map(HabitCheck.fromRecord).toList();
      _firstDay = readFirstDay(settings);
    });
  }

  Map<String, List<String>> get _datesByHabit {
    final map = <String, List<String>>{};
    for (final check in _checks) {
      map.putIfAbsent(check.habitId, () => []).add(check.dateKey);
    }
    return map;
  }

  /// Adds or removes today's check-in for [habit] — the one-tap interaction
  /// the whole screen is arranged around. The record id is the habit and the
  /// civil date, so a day can never hold two.
  Future<void> _toggle(Habit habit) async {
    if (_writing.contains(habit.id)) return;
    setState(() => _writing.add(habit.id));
    try {
      final today = dateKeyOf(DateTime.now());
      final id = HabitCheck.idFor(habit.id, today);
      final existing = await widget.store.get('check', id);
      if (existing == null) {
        await widget.store.put('check', id, {
          'habit': habit.id,
          'date': today,
          'at': DateTime.now().toIso8601String(),
        });
      } else {
        await widget.store.delete('check', id);
      }
    } catch (_) {
      writeError();
    } finally {
      if (mounted) setState(() => _writing.remove(habit.id));
    }
  }

  Future<void> _newHabit() => showHabitEditSheet(context, widget.store);

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final active = _habits.where((h) => !h.archived).toList();
    final doneToday = active
        .where(
          (h) =>
              _datesByHabit[h.id]?.contains(dateKeyOf(DateTime.now())) ?? false,
        )
        .length;

    return Scaffold(
      appBar: AppBar(
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
            onPressed: () => unawaited(
              Navigator.push(
                context,
                NexPageRoute<void>(
                  builder: (_) => ArchiveScreen(store: widget.store),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('habits-new'),
        onPressed: () => unawaited(_newHabit()),
        icon: const Icon(Icons.add),
        label: Text(strings(context, 'newHabit')),
      ),
      body: recordsBody(
        _habits.isEmpty
            ? NexEmptyState(
                icon: Icons.event_repeat_outlined,
                message: strings(context, 'empty'),
                action: FilledButton.icon(
                  onPressed: () => unawaited(_newHabit()),
                  icon: const Icon(Icons.add),
                  label: Text(strings(context, 'newHabit')),
                ),
              )
            : active.isEmpty
            ? NexEmptyState(
                icon: Icons.archive_outlined,
                message: strings(context, 'allArchived'),
                action: FilledButton.icon(
                  onPressed: () => unawaited(_newHabit()),
                  icon: const Icon(Icons.add),
                  label: Text(strings(context, 'newHabit')),
                ),
              )
            : ListView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.lg + nexBottomInset(context),
                ),
                children: [
                  NexShelfHeading(
                    icon: Icons.today_outlined,
                    title: strings(context, 'today'),
                    note: strings(context, 'todaySummary', {
                      'done': doneToday,
                      'total': active.length,
                    }),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  for (final (index, habit) in active.indexed)
                    HabitRow(
                      firstDay: _firstDay,
                      busy: _writing.contains(habit.id),
                      index: index,
                      count: active.length,
                      habit: habit,
                      dates: _datesByHabit[habit.id] ?? const [],
                      onToggle: () => unawaited(_toggle(habit)),
                      onOpen: () => unawaited(
                        Navigator.push(
                          context,
                          NexPageRoute<void>(
                            builder: (_) => HabitDetailScreen(
                              store: widget.store,
                              habitId: habit.id,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: NexSpacing.xl),
                ],
              ),
        () => unawaited(_load()),
      ),
    );
  }
}
