import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_calendar.dart';
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
  Future<void> _toggleDay(String day) async {
    if (_writing) return;
    setState(() => _writing = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final errorMessage = habitsStrings(context, 'saveError');
    try {
      final id = HabitCheck.idFor(widget.habitId, day);
      final existing = await widget.store.get('check', id);
      if (existing == null) {
        await widget.store.put('check', id, {
          'habit': widget.habitId,
          'date': day,
          'at': DateTime.now().toIso8601String(),
        });
      } else {
        await widget.store.delete('check', id);
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(habitsStrings(context, 'checkinDeleted')),
              action: SnackBarAction(
                label: l10n.undo,
                onPressed: () => unawaited(
                  widget.store.put('check', id, existing).catchError((
                    Object _,
                  ) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(errorMessage)),
                    );
                  }),
                ),
              ),
            ),
          );
        }
      }
    } catch (_) {
      writeError();
    } finally {
      if (mounted) setState(() => _writing = false);
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
      showHabitEditSheet(context, widget.store, habit: _habit);

  Future<void> _setArchived(bool archived) async {
    final habit = _habit;
    if (habit == null || _writing) return;
    setState(() => _writing = true);
    try {
      await widget.store.put(
        'habit',
        habit.id,
        habit.toJson()..['archived'] = archived,
      );
      // An archived habit stops nudging; the daily reminder is its own
      // record, so it goes with it rather than ringing for nothing.
      if (archived) await _clearReminder(habit.id);
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
              bundle.restore().catchError((Object _) {
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
    final standing = HabitMath.standing(
      habit,
      _dates(),
      DateTime.now(),
      firstDay: _firstDay,
    );
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
                PopupMenuItem(
                  value: 'archive',
                  child: Text(strings(context, 'archive')),
                )
              else
                PopupMenuItem(
                  value: 'unarchive',
                  child: Text(strings(context, 'unarchive')),
                ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  AppLocalizations.of(context).delete,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
            FilledButton.icon(
              key: ValueKey('habit-toggle-${habit.id}'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _writing ? null : () => unawaited(_toggleToday()),
              icon: Icon(standing.todayDone ? Icons.undo : Icons.check_rounded),
              label: Text(
                strings(
                  context,
                  standing.todayDone ? 'undoCheckIn' : 'checkIn',
                ),
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            HabitStreakPanel(habit: habit, standing: standing),
            const SizedBox(height: NexSpacing.md),
            HabitRatePanel(
              habit: habit,
              dateKeys: _dates(),
              firstDay: _firstDay,
            ),
            const SizedBox(height: NexSpacing.md),
            HabitCalendarPanel(
              doneKeys: _dates().where((k) => k.isNotEmpty).toSet(),
              firstDay: _firstDay,
              busy: _writing,
              onToggle: (day) => unawaited(_toggleDay(day)),
            ),
            const SizedBox(height: NexSpacing.md),
            HabitTwoWeekDots(standing: standing),
            if (habit.note.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.md),
              HabitNotePanel(note: habit.note),
            ],
            if (!habit.archived) ...[
              const SizedBox(height: NexSpacing.md),
              HabitReminderTile(store: widget.store, habitId: habit.id),
            ],
            const SizedBox(height: NexSpacing.lg),
            NexShelfHeading(
              icon: Icons.history_outlined,
              title: strings(context, 'history'),
            ),
            const SizedBox(height: NexSpacing.sm),
            HabitHistory(checks: _checks),
            const SizedBox(height: NexSpacing.xl),
          ],
        ),
        () => unawaited(_load()),
      ),
    );
  }

  Iterable<String> _dates() => _checks.map((c) => c.dateKey);
}
