import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'craving_list.dart';
import 'craving_sheet.dart';
import 'sos_sheet.dart';
import 'smoke_panels.dart';
import 'module.dart';
import 'store_state.dart';
import 'quit_habits.dart';
import 'quit_model.dart';
import 'quit_widgets.dart';
import 'setup_sheet.dart';
import 'smoke_math.dart';

/// The smoke-free dashboard: the days kept, the honest estimates built from
/// the person's own baseline, and the cravings logged in one tap. The
/// primary action is logging a craving — the counter is calm on purpose.
///
/// One screen for one habit ([habit], a [QuitAttempt.key]): cigarettes —
/// what the module was — unless Quit Habits opened it for another.
class SmokeFreeScreen extends StatefulWidget {
  const SmokeFreeScreen({
    super.key,
    required this.store,
    this.habit = defaultHabit,
  });

  final NexModuleStore store;
  final String habit;

  @override
  State<SmokeFreeScreen> createState() => _SmokeFreeScreenState();
}

class _SmokeFreeScreenState extends State<SmokeFreeScreen>
    with WidgetsBindingObserver, StoreState<SmokeFreeScreen> {
  List<QuitAttempt> _attempts = const [];
  List<Craving> _cravings = const [];
  StreamSubscription<void>? _changes;
  int _loadToken = 0;
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
    final token = ++_loadToken;
    final quits = await widget.store.list('quit');
    final cravings = await widget.store.list('craving');
    if (!mounted || token != _loadToken) return;
    setState(() {
      _attempts = [
        for (final a in quits.map(QuitAttempt.fromRecord))
          if (a.key == widget.habit) a,
      ];
      _cravings = SmokeMath.cravingsNewestFirst([
        for (final c in cravings.map(Craving.fromRecord))
          if (c.habit == widget.habit) c,
      ]);
    });
  }

  Future<bool> _guard(Future<void> Function() action) async {
    if (_writing) return false;
    setState(() => _writing = true);
    try {
      await action();
      if (mounted) await _load();
      return true;
    } catch (_) {
      writeError();
      return false;
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _setup({QuitAttempt? editing}) =>
      showSetupSheet(context, widget.store, editing: editing);

  QuitPreset get _preset => quitPresetOf(
    widget.habit.startsWith('custom:') ? 'custom' : widget.habit,
  );

  /// Ends the active attempt and — when [restart] — starts a new one today
  /// with the same baseline. Either way, the attempt stays in history and
  /// every craving keeps its place.
  Future<bool> _recordLapse({required bool restart, String reason = 'lapse'}) =>
      _guard(() async {
        final active = SmokeMath.activeAttempt(_attempts);
        if (active == null) return;
        final now = DateTime.now();
        final raw = await widget.store.get('quit', active.id);
        if (raw == null) throw StateError('Attempt missing');
        final restartId = widget.store.newId();
        try {
          await widget.store.put('quit', active.id, {
            ...raw,
            ...active.toJson(endedAt: now, endedWhy: reason),
          });
          if (restart) {
            // The same baseline, name, reason and goal, from today.
            await widget.store.put('quit', restartId, {
              ...active.toJson(),
              'startedAt': now.toIso8601String(),
              'endedAt': null,
              'endedWhy': null,
            });
          }
        } catch (_) {
          if (restart) await widget.store.delete('quit', restartId);
          await widget.store.put('quit', active.id, raw);
          rethrow;
        }
      });

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final active = SmokeMath.activeAttempt(_attempts);
    final past = SmokeMath.pastAttempts(_attempts);

    return Scaffold(
      appBar: NexAppBar(
        title: Text(
          active != null
              ? quitHabitLabel(context, active)
              : widget.habit.startsWith('custom:')
              ? (past.isEmpty
                    ? strings(context, 'habit_custom')
                    : quitHabitLabel(context, past.first))
              : strings(context, 'habit_${_preset.key}'),
        ),
        actions: [
          if (active != null)
            IconButton(
              key: const ValueKey('smoke-edit-baseline'),
              tooltip: strings(context, 'editBaseline'),
              icon: const Icon(Icons.tune_outlined),
              onPressed: _writing
                  ? null
                  : () => unawaited(_setup(editing: active)),
            ),
          if (active != null)
            NexPopupMenuButton<String>(
              key: const ValueKey('smoke-menu'),
              tooltip: strings(context, 'more'),
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'lapse') unawaited(_askLapse());
                if (value == 'restart') unawaited(_askRestart());
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'restart',
                  child: Text(strings(context, 'restartAttempt')),
                ),
                PopupMenuItem(
                  value: 'lapse',
                  child: Text(
                    strings(
                      context,
                      widget.habit == defaultHabit
                          ? 'recordLapse'
                          : 'recordLapseGeneric',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: active == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('smoke-log-craving'),
              onPressed: _writing
                  ? null
                  : () => unawaited(_logCraving(context)),
              icon: const Icon(Icons.add),
              label: Text(strings(context, 'logCraving')),
            ),
      body: recordsBody(
        StoreScope(
          store: widget.store,
          child: active == null
              ? NoAttempt(
                  onStart: () => unawaited(
                    showSetupSheet(
                      context,
                      widget.store,
                      habit: past.isEmpty ? _preset.key : past.first.habit,
                      name: past.isEmpty ? '' : past.first.name,
                    ),
                  ),
                  past: past,
                  cravings: _cravings,
                )
              : SmokeDashboard(
                  attempt: active,
                  past: past,
                  cravings: _cravings,
                  onLapse: () => unawaited(_askLapse()),
                  onHelp: () =>
                      unawaited(showSosSheet(context, widget.store, active)),
                ),
        ),
        () => unawaited(_load()),
      ),
    );
  }

  Future<void> _logCraving(BuildContext context) =>
      showCravingSheet(context, widget.store, habit: widget.habit);

  Future<void> _askRestart() async {
    if (_writing) return;
    final choice = await nexShowDialog<bool>(
      context: context,
      builder: (dialog) => NexAlertDialog(
        title: Text(smokeFreeStrings(dialog, 'restartAttempt')),
        content: NexDialogBody(
          child: Text(smokeFreeStrings(dialog, 'restartBody')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(AppLocalizations.of(dialog).cancel),
          ),
          FilledButton(
            key: const ValueKey('smoke-confirm-restart'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(smokeFreeStrings(dialog, 'restartAttempt')),
          ),
        ],
      ),
    );
    if (choice != true || !mounted) return;
    final saved = await _recordLapse(restart: true, reason: 'restart');
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(smokeFreeStrings(context, 'newAttemptStarted'))),
      );
    }
  }

  Future<void> _askLapse() async {
    final strings = smokeFreeStrings;
    final l10n = AppLocalizations.of(context);
    final restart = await nexShowDialog<bool>(
      context: context,
      builder: (dialogContext) => NexAlertDialog(
        title: Text(strings(dialogContext, 'lapseTitle')),
        content: NexDialogBody(
          child: Text(strings(dialogContext, 'lapseBody')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('smoke-lapse-just'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings(dialogContext, 'lapseJust')),
          ),
          FilledButton(
            key: const ValueKey('smoke-lapse-restart'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings(dialogContext, 'lapseRestart')),
          ),
        ],
      ),
    );
    if (restart == null) return;
    final saved = await _recordLapse(restart: restart);
    if (!saved) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          strings(context, restart ? 'newAttemptStarted' : 'lapseRecorded'),
        ),
      ),
    );
  }
}
