import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'local_writes.dart';
import 'medicine_detail.dart';
import 'medicine_dialogs.dart';
import 'medicine_fields.dart';
import 'medicine_logic.dart';
import 'medicine_models.dart';
import 'medicine_repository.dart';
import 'medicine_schedule.dart';
import 'medicine_shared.dart';
import 'medicine_strings.dart';

part 'medicine_today_rows.dart';

/// One routine moment of one medicine on one day.
class _DoseSlot {
  const _DoseSlot({
    required this.medicine,
    required this.at,
    required this.day,
    required this.time,
    required this.yesterday,
    this.log,
  });

  final ModuleRecord medicine;
  final DateTime at;

  /// The civil day the moment belongs to, so two days can never share a
  /// key or a row's identity.
  final String day;
  final String time;
  final bool yesterday;

  /// The dose already logged for this moment, if any. Nothing is inferred:
  /// an unlogged moment simply has none.
  final ModuleRecord? log;
}

/// «Today» — the routine the person wrote, for today, with Taken and
/// Skipped one tap away, and yesterday's unrecorded moments offered the
/// next morning without ever calling them missed.
///
/// The module never decides whether a dose was needed or taken; it only
/// writes down what the person says happened, at the moment the routine
/// named.
class MedicineTodayPage extends StatefulWidget {
  const MedicineTodayPage({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<MedicineTodayPage> createState() => _MedicineTodayPageState();
}

class _MedicineTodayPageState extends State<MedicineTodayPage>
    with WidgetsBindingObserver {
  List<ModuleRecord> _medicines = const [];
  List<ModuleRecord> _doses = const [];
  StreamSubscription<void>? _changes;
  int _loadSeq = 0;
  bool _loading = true;
  bool _loadFailed = false;

  /// The moments a write is in flight for, as `day|medicine|time`. Only
  /// those rows’ buttons wait; the rest of the page stays usable, so
  /// logging a morning’s doses is one tap after another.
  final Set<String> _busySlots = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A page left open overnight must not still say "today" about
    // yesterday: coming back to the app rereads the day.
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    try {
      await LocalWrites.recover(widget.store);
      final medicines = await widget.store.list(MedicineModels.medicine);
      final doses = await widget.store.list(MedicineModels.dose);
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _medicines = medicines;
        _doses = doses;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// Every routine moment of [day] for the medicines still on the list,
  /// matched to the log that answers it.
  List<_DoseSlot> _slotsFor(DateTime day, {required bool yesterday}) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day, 23, 59, 59);
    final out = <_DoseSlot>[];
    for (final medicine in _medicines) {
      final body = medicine.body;
      if (MedicineModels.readArchived(body)) {
        continue;
      }
      final schedule = MedicineSchedule.of(body);
      if (!schedule.hasTimes) {
        continue;
      }
      for (final at in schedule.occurrences(from: start, until: end)) {
        final time = _hhmm(at);
        out.add(
          _DoseSlot(
            medicine: medicine,
            at: at,
            day: '${at.year}-${at.month}-${at.day}',
            time: time,
            yesterday: yesterday,
            log: _logFor(medicine.id, at, time),
          ),
        );
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  ModuleRecord? _logFor(String medicineId, DateTime at, String time) {
    for (final dose in MedicineLogic.dosesFor(_doses, medicineId)) {
      if (MedicineShared.answers(dose, medicineId, at, time)) {
        return dose;
      }
    }
    return null;
  }

  String _slotKey(_DoseSlot slot) =>
      '${slot.day}|${slot.medicine.id}|${slot.time}';

  Future<void> _log(_DoseSlot slot, String action) async {
    final key = _slotKey(slot);
    if (_busySlots.contains(key) || slot.log != null) {
      return;
    }
    setState(() => _busySlots.add(key));
    try {
      await MedicineRepository.log(
        widget.store,
        slot.medicine.id,
        action,
        at: slot.at,
        slot: slot.time,
      );
      await _load();
    } catch (_) {
      if (mounted) {
        NexBannerHost.of(context)?.show(
          kind: NexBannerKind.failed,
          message: medicineStrings(context, 'saveFailed'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busySlots.remove(key));
      }
    }
  }

  Future<void> _correct(_DoseSlot slot) async {
    final log = slot.log;
    final key = _slotKey(slot);
    if (_busySlots.contains(key) || log == null) {
      return;
    }
    setState(() => _busySlots.add(key));
    try {
      final undo = await MedicineRepository.deleteDose(
        widget.store,
        slot.medicine.id,
        log.id,
      );
      if (!mounted) {
        return;
      }
      MedicineDialogs.offerUndo(
        NexBannerHost.of(context),
        medicineStrings(context, 'doseDeleted'),
        AppLocalizations.of(context).undo,
        undo,
      );
      await _load();
    } catch (_) {
      if (mounted) {
        NexBannerHost.of(context)?.show(
          kind: NexBannerKind.failed,
          message: medicineStrings(context, 'saveFailed'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busySlots.remove(key));
      }
    }
  }

  Future<void> _open(ModuleRecord record) async {
    await nexShowSheet<void>(
      context: context,
      builder: (_) => MedicineDetailSheet(store: widget.store, record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = medicineStrings;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = _slotsFor(now, yesterday: false);
    final yesterday = _slotsFor(
      now.subtract(const Duration(days: 1)),
      yesterday: true,
    ).where((slot) => slot.log == null).toList();
    // The one moment to act on: the first open one still ahead. Everything
    // else on the page is the same panel; this one carries its own heading,
    // so a full list does not have to be scanned to find it.
    _DoseSlot? next;
    for (final slot in today) {
      if (slot.log == null && !slot.at.isBefore(now)) {
        next = slot;
        break;
      }
    }

    return Scaffold(
      appBar: NexAppBar(title: Text(strings(context, 'today'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(strings(context, 'loadFailed')),
                  TextButton(
                    onPressed: () => unawaited(_load()),
                    child: Text(strings(context, 'retry')),
                  ),
                ],
              ),
            )
          : today.isEmpty && yesterday.isEmpty
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: NexEmptyState(
                    key: const ValueKey('medicine-today-empty'),
                    icon: Icons.schedule_outlined,
                    message: strings(context, 'todayEmpty'),
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.xl,
              ),
              children: [
                for (final slot in today)
                  _slotRow(
                    context,
                    slot,
                    strings: strings,
                    isNext: identical(slot, next),
                  ),
                if (yesterday.isNotEmpty) ...[
                  const SizedBox(height: NexSpacing.md),
                  Text(
                    strings(context, 'yesterdayNoRecord'),
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final slot in yesterday)
                    _slotRow(context, slot, strings: strings),
                ],
                const SizedBox(height: NexSpacing.md),
                Text(
                  strings(context, 'safetyNote'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  static String _hhmm(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}
