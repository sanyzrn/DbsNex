import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_calendar.dart';
import 'habit_log.dart';
import 'habit_visuals.dart';
import 'habit_edit_sheet.dart';
import 'habit_math.dart';
import 'habit_model.dart';
import 'habit_reminder.dart';
import 'habit_stats.dart';
import 'module.dart';
import 'store_state.dart';
import 'record_bundle.dart';
import 'week_settings.dart';

/// One habit's whole story: its streak (and any forgiven interval, said out
/// loud), the last two weeks as a quiet row of marks, and every recent
/// check-in. Editing, archiving and deleting live here too.
class HabitDetailScreen extends StatefulWidget {
  const HabitDetailScreen({
    super.key,
    required this.store,
    required this.habitId,
  });

  final NexModuleStore store;
  final String habitId;

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen>
    with WidgetsBindingObserver, StoreState<HabitDetailScreen> {
  Habit? _habit;
  List<HabitCheck> _checks = const [];
  StreamSubscription<void>? _changes;
  int _loadToken = 0;
  int _firstDay = DateTime.saturday;
  bool _writing = false;

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

  Future<void> _load() => readRecords(_read);

  Future<void> _read() async {
    await RecordBundle.recover(widget.store);
    final token = ++_loadToken;
    final body = await widget.store.get('habit', widget.habitId);
    final checks = await widget.store.list('check');
    final settings = await widget.store.get('settings', 'week');
    if (!mounted || token != _loadToken) return;
    if (body == null) {
      if (_writing) return;
      // The habit was deleted while this page was open — most likely by
      // this page. There is nothing left to show, so go back.
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _habit = Habit.fromBody(widget.habitId, body);
      _firstDay = readFirstDay(settings);
      _checks =
          checks
              .map(HabitCheck.fromRecord)
              .where((c) => c.habitId == widget.habitId)
              .toList()
            ..sort(newestCheckFirst);
    });
  }

  /// Today's check-in, from this page exactly as from Today — including the
  /// Undo snackbar when a check-in is taken back.
  Future<void> _toggleToday() => _toggleDay(dateKeyOf(DateTime.now()));

  /// A day's check-in: made if there is none, taken back (with Undo) if
  /// there is. The calendar uses it for any day up to today.
  Future<void> _toggleDay(String day, {bool addOne = false}) async {
    final habit = _habit;
    if (_writing || habit == null) return;
    setState(() => _writing = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final errorMessage = habitsStrings(context, 'saveError');
    final removed = habitsStrings(context, 'checkinDeleted');
    final log = HabitLog(widget.store, l10n);
    try {
      Map<String, Object?>? existing;
      if (habit.counted) {
        final body = await widget.store.get('check', HabitCheck.idFor(habit.id, day));
        final amount = body == null ? 0 : (body['amount'] is int ? body['amount'] as int : habit.goal);
        if (!mounted) return;
        final value = addOne ? amount + 1 : await showHabitAmountSheet(context, habit: habit, current: amount);
        if (value == null || value == amount) return;
        existing = await log.setAmount(habit, day, value);
        if (value != 0) return;
      } else {
        existing = await log.toggle(habit, day);
      }
      if (existing != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(removed), action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => unawaited(log.restore(habit, day, existing).catchError((Object _) {
            messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
          })),
        )));
      }
    } catch (_) { writeError(); }
    finally { if (mounted) setState(() => _writing = false); }
  }

  Future<void> _preserveReminder(Habit habit) async {
    final reminder = await habitReadReminder(widget.store, habit.id);
    if (reminder.on && await widget.store.get(habitRemindKind, habit.id) == null) {
      await widget.store.put(habitRemindKind, habit.id,
        {'v': 1, 'on': true, 'minutes': reminder.minutes});
    }
  }

  Future<void> _clearReminder(String id) async {
    try {
      await widget.store.clearReminder('habit:$id');
    } catch (_) {
      // Rings once at most: the restore on launch drops it for a missing
      // or archived habit.
    }
  }

  Future<void> _edit() =>
      showHabitEditSheet(context, widget.store, habit: _habit, firstDay: _firstDay);

  Future<void> _setArchived(bool archived) async {
    final habit = _habit;
    if (habit == null || _writing) return;
    setState(() => _writing = true);
    final l10n = AppLocalizations.of(context);
    try {
      await _preserveReminder(habit);
      await widget.store.put(
        'habit',
        habit.id,
        habit.toJson()..['archived'] = archived,
      );
      // An archived habit stops nudging; the daily reminder is its own
      // record, so it goes with it rather than ringing for nothing.
      if (archived) {
        await _clearReminder(habit.id);
      } else {
        try { await habitArmReminder(widget.store, l10n,
          Habit.fromBody(habit.id, habit.toJson()..['archived'] = false)); } catch (_) {}
      }
    } catch (_) {
      writeError();
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  /// Deletes the habit and every check-in it owns, then offers Undo — which
  /// must bring back the whole history, not only the name. The snackbar is
  /// posted through a messenger captured before any await, and outlives
  /// this page's own departure.
  Future<void> _delete() async {
    final habit = _habit;
    if (habit == null || _writing) return;
    setState(() => _writing = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final errorMessage = habitsStrings(context, 'saveError');
    try {
      await _preserveReminder(habit);
      final bundle = await RecordBundle.capture(
        widget.store,
        'habit',
        habit.id,
        'check',
        'habit',
      );
      await bundle.delete();
      await _clearReminder(habit.id);
      if (!mounted) return;
      Navigator.of(context).maybePop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(habitsStrings(context, 'habitDeleted')),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () => unawaited(
              bundle.restore().then((_) async {
                await habitArmReminder(widget.store, l10n, habit);
              }).catchError((Object _) {
                messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
              }),
            ),
          ),
        ),
      );
    } catch (_) {
      writeError();
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final habit = _habit;
    if (habit == null) {
      return Scaffold(
        appBar: NexAppBar(),
        body: recordsBody(const SizedBox(), () => unawaited(_load())),
      );
    }
    final strings = habitsStrings;
    final standing = HabitMath.fromChecks(
      habit,
      _checks,
      DateTime.now(),
      firstDay: _firstDay,
    );
    final color = habitColor(context, habit);
    final logged = HabitMath.loggedDays(habit, _checks, DateTime.now());
    final amounts = {for (final e in logged.entries) dateKeyOf(e.key): e.value};
    final name = habit.name.isEmpty ? strings(context, 'untitled') : habit.name;

    return Scaffold(
      appBar: NexAppBar(
        title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('habit-edit'),
            tooltip: strings(context, 'editHabit'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: _writing ? null : () => unawaited(_edit()),
          ),
          NexPopupMenuButton<String>(
            key: const ValueKey('habit-menu'),
            tooltip: strings(context, 'more'),
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'archive') unawaited(_setArchived(true));
              if (value == 'unarchive') unawaited(_setArchived(false));
              if (value == 'delete') unawaited(_delete());
            },
            itemBuilder: (context) => [
              if (!habit.archived)
                nexMenuItem(
                  value: 'archive',
                  icon: Icons.archive_outlined,
                  label: strings(context, 'archive'),
                )
              else
                nexMenuItem(
                  value: 'unarchive',
                  icon: Icons.unarchive_outlined,
                  label: strings(context, 'unarchive'),
                ),
              nexMenuItem(
                value: 'delete',
                icon: Icons.delete_outline,
                label: AppLocalizations.of(context).delete,
                destructive: true,
              ),
            ],
          ),
        ],
      ),
      body: recordsBody(
        ListView(
          padding: EdgeInsetsDirectional.fromSTEB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            NexSpacing.lg + nexBottomInset(context),
          ),
          children: [
            HabitHero(habit: habit, standing: standing, firstDay: _firstDay),
            const SizedBox(height: NexSpacing.md),
            Row(children: [
              Expanded(child: FilledButton.icon(
                key: ValueKey('habit-toggle-${habit.id}'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: color),
                onPressed: _writing ? null : () => unawaited(_toggleToday()),
                icon: Icon(habit.counted ? Icons.tune : standing.todayDone ? Icons.undo : Icons.check_rounded),
                label: Text(habit.counted
                  ? strings(context, 'logAmount', {'amount': standing.todayAmount, 'goal': habit.goal})
                  : strings(context, standing.todayDone ? 'undoCheckIn' : 'checkIn')),
              )),
              if (habit.counted) ...[
                const SizedBox(width: NexSpacing.sm),
                IconButton.filledTonal(
                  key: const ValueKey('habit-add-one'),
                  tooltip: strings(context, 'addOne'),
                  onPressed: _writing ? null : () => unawaited(_toggleDay(dateKeyOf(DateTime.now()), addOne: true)),
                  icon: const Icon(Icons.add),
                ),
              ],
            ]),
            const SizedBox(height: NexSpacing.md),
            HabitStatTiles(habit: habit, standing: standing, dateKeys: amounts.keys,
              amounts: amounts, firstDay: _firstDay, color: color),
            const SizedBox(height: NexSpacing.md),
            HabitSeasonPanel(habit: habit, logged: logged, color: color, firstDay: _firstDay),
            const SizedBox(height: NexSpacing.md),
            HabitCalendarPanel(habit: habit, logged: logged, color: color,
              firstDay: _firstDay, busy: _writing, onToggle: (day) => unawaited(_toggleDay(day))),
            if (habit.note.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.md),
              HabitNotePanel(note: habit.note),
            ],
            if (!habit.archived) ...[
              const SizedBox(height: NexSpacing.md),
              HabitReminderTile(store: widget.store, habit: habit, color: color),
            ],
            const SizedBox(height: NexSpacing.lg),
            NexShelfHeading(
              icon: Icons.history_outlined,
              title: strings(context, 'history'),
            ),
            const SizedBox(height: NexSpacing.sm),
            HabitHistory(habit: habit, checks: _checks, color: color),
            const SizedBox(height: NexSpacing.xl),
          ],
        ),
        () => unawaited(_load()),
      ),
    );
  }


}

