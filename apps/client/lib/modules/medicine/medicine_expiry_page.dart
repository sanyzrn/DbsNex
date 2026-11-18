import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'local_writes.dart';
import 'medicine_detail.dart';
import 'medicine_logic.dart';
import 'medicine_models.dart';
import 'medicine_strings.dart';

/// One dated thing in the cabinet: a box's own date, or the single expiry
/// a record written before boxes still carries.
class _ExpiryEntry {
  const _ExpiryEntry({
    required this.id,
    required this.name,
    required this.date,
    required this.medicine,
    this.units,
  });

  final String id;
  final String name;
  final DateTime date;
  final ModuleRecord medicine;
  final int? units;
}

/// «Expiry» — what the person dated, the ones already past first, then
/// the ones inside the next three months. It shows their dates only; the
/// module makes no judgement about whether a medicine is safe.
class MedicineExpiryPage extends StatefulWidget {
  const MedicineExpiryPage({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<MedicineExpiryPage> createState() => _MedicineExpiryPageState();
}

class _MedicineExpiryPageState extends State<MedicineExpiryPage> {
  List<ModuleRecord> _medicines = const [];
  List<ModuleRecord> _boxes = const [];
  StreamSubscription<void>? _changes;
  int _loadSeq = 0;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    try {
      await LocalWrites.recover(widget.store);
      final medicines = await widget.store.list(MedicineModels.medicine);
      final boxes = await widget.store.list(MedicineModels.box);
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _medicines = medicines;
        _boxes = boxes;
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

  List<_ExpiryEntry> _entries() {
    final now = DateTime.now();
    final out = <_ExpiryEntry>[];
    final byId = {for (final medicine in _medicines) medicine.id: medicine};
    for (final medicine in _medicines) {
      final body = medicine.body;
      final legacy = MedicineModels.readDate(body, 'expiresAt');
      if (legacy != null) {
        final state = MedicineLogic.expiryBucket(legacy, now);
        if (state.expired || state.soon) {
          out.add(
            _ExpiryEntry(
              id: 'medicine-${medicine.id}',
              name: MedicineModels.readString(body, 'name'),
              date: legacy,
              medicine: medicine,
            ),
          );
        }
      }
    }
    for (final box in _boxes) {
      final date = MedicineModels.readDay(box.body, 'expiresAt');
      final medicine = byId[MedicineModels.readString(box.body, 'medicineId')];
      if (date == null || medicine == null) {
        continue;
      }
      final state = MedicineLogic.expiryBucket(date, now);
      if (!state.expired && !state.soon) {
        continue;
      }
      out.add(
        _ExpiryEntry(
          id: box.id,
          name: MedicineModels.readString(medicine.body, 'name'),
          date: date,
          medicine: medicine,
          units: MedicineModels.readCount(box.body, 'units'),
        ),
      );
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
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
    final entries = _entries();
    final now = DateTime.now();
    final expired = entries
        .where(
          (entry) =>
              !entry.date.isAfter(DateTime(now.year, now.month, now.day)),
        )
        .toList();
    final soon = entries
        .where(
          (entry) => entry.date.isAfter(DateTime(now.year, now.month, now.day)),
        )
        .toList();

    return Scaffold(
      appBar: NexAppBar(title: Text(strings(context, 'expiryTitle'))),
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
          : entries.isEmpty
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: NexEmptyState(
                    key: const ValueKey('medicine-expiry-empty'),
                    icon: Icons.event_busy_outlined,
                    message: strings(context, 'noneExpiring'),
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
                Text(
                  strings(context, 'expiryIntro'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                if (expired.isNotEmpty) ...[
                  Text(
                    strings(context, 'expiredSection'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  for (final entry in expired)
                    _row(context, entry, expired: true),
                  const SizedBox(height: NexSpacing.md),
                ],
                if (soon.isNotEmpty) ...[
                  Text(
                    strings(context, 'soonSection'),
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final entry in soon)
                    _row(context, entry, expired: false),
                ],
              ],
            ),
    );
  }

  Widget _row(
    BuildContext context,
    _ExpiryEntry entry, {
    required bool expired,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('medicine-expiry-${entry.id}'),
      contentPadding: EdgeInsets.zero,
      onTap: () => unawaited(_open(entry.medicine)),
      leading: Icon(
        expired ? Icons.error_outline : Icons.event_outlined,
        color: expired
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Text(
        [
          nexModuleDateLabel(context, entry.date),
          if (entry.units != null)
            medicineStrings(context, 'boxUnits', {'count': entry.units}),
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: expired ? theme.colorScheme.error : null,
        ),
      ),
    );
  }
}
