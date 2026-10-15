import 'dart:async';
import 'local_writes.dart';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'medicine_detail.dart';
import 'medicine_editor.dart';
import 'medicine_logic.dart';
import 'medicine_models.dart';
import 'medicine_strings.dart';

part 'medicine_screen_body.dart';

/// «My medicines» — the list a person reads on opening the app: what is
/// active, what is archived, and nothing that claims to have been
/// scheduled or checked while they were away.
class MedicineScreen extends StatefulWidget {
  const MedicineScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends State<MedicineScreen>
    with WidgetsBindingObserver {
  List<ModuleRecord> _medicines = const [];
  bool _showArchived = false;

  StreamSubscription<void>? _changes;

  /// A load in flight is newer than one that has not started, so a slow
  /// earlier read cannot repaint over a later one.
  int _loadSeq = 0;
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    try {
      await LocalWrites.recover(widget.store);

      final medicines = await widget.store.list(MedicineModels.medicine);
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _medicines = medicines;
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

  // ------------------------------------------------------------ openings

  Future<void> _add() async {
    if (_busy || _loading || _loadFailed) {
      return;
    }
    setState(() => _busy = true);
    try {
      await nexShowSheet<void>(
        context: context,
        dismissible: false,
        swipeToClose: true,
        builder: (_) => MedicineEditorSheet(
          store: widget.store,
          existingNames: [
            for (final r in _medicines)
              if (!MedicineModels.readArchived(r.body))
                MedicineModels.readString(r.body, 'name'),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openDetail(ModuleRecord record) async {
    await nexShowSheet<void>(
      context: context,
      builder: (_) => MedicineDetailSheet(store: widget.store, record: record),
    );
  }

  // -------------------------------------------------------------- changes

  Future<void> _unarchive(ModuleRecord record) async {
    await _work(
      () => LocalWrites.patch(
        widget.store,
        MedicineModels.medicine,
        record.id,
        {'archived': false},
      ),
    );
  }

  // -------------------------------------------------------------- build

  Widget _readError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(medicineStrings(context, 'loadFailed')),
          TextButton(
            onPressed: () => unawaited(_load()),
            child: Text(medicineStrings(context, 'retry')),
          ),
        ],
      ),
    ),
  );
  Future<void> _work(Future<void> Function() run) async {
    if (_busy || _loading || _loadFailed) {
      return;
    }
    setState(() => _busy = true);
    try {
      await run();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(medicineStrings(context, 'saveFailed'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _paint(VoidCallback change) {
    if (mounted) {
      setState(change);
    }
  }

  @override
  Widget build(BuildContext context) => _view(context);
}

/// One medicine on the active list: the name as it was written, the
/// strength beside it, and the states worth reading on opening — stock,
/// expiry, refill — all from numbers the person wrote themselves.
class _MedicineRow extends StatelessWidget {
  const _MedicineRow({required this.record, required this.onOpen});

  final ModuleRecord record;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = medicineStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = record.body;
    final name = MedicineModels.readString(body, 'name');
    final strength = MedicineModels.readString(body, 'strength');
    final packageUnit = MedicineModels.readString(body, 'package');
    final quantity = MedicineModels.readCount(body, 'quantity');
    final refillThreshold = MedicineModels.readCount(body, 'refillThreshold');
    final expiry = MedicineLogic.expiryOf(
      MedicineModels.readDate(body, 'expiresAt'),
      DateTime.now(),
    );

    final marks = <Widget>[
      if (quantity != null)
        Text(
          quantity == 0
              ? strings(context, 'quantityNone')
              : strings(context, 'quantityLeft', {
                  'count': quantity,
                  'unit': packageUnit.isEmpty
                      ? MedicineModels.readString(body, 'strength')
                      : packageUnit,
                }),
          style: theme.textTheme.bodySmall?.copyWith(
            color: MedicineLogic.needsRefill(quantity, refillThreshold)
                ? scheme.error
                : scheme.onSurfaceVariant,
          ),
        ),
      if (expiry.expired)
        Text(
          strings(context, 'expired'),
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
        )
      else if (expiry.soon)
        Text(
          strings(context, 'expiringSoon'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      if (MedicineLogic.needsRefill(quantity, refillThreshold) && quantity != 0)
        Text(
          strings(context, 'refillSoon'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.xs),
      child: ListTile(
        key: ValueKey('medicine-row-${record.id}'),
        onTap: onOpen,
        leading: NexIconTile(
          Icons.medication_outlined,
          color: NexHue.rose.of(theme.brightness),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: marks.isEmpty
            ? (strength.isEmpty ? null : Text(strength, maxLines: 1))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (strength.isNotEmpty) Text(strength, maxLines: 1),
                  Wrap(spacing: NexSpacing.sm, children: marks),
                ],
              ),
      ),
    );
  }
}

/// One archived medicine, one tap from coming back.
class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({
    required this.record,
    required this.onUnarchive,
    required this.onOpen,
  });

  final ModuleRecord record;
  final VoidCallback onUnarchive;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('medicine-archived-${record.id}'),
      onTap: onOpen,
      leading: NexIconTile(
        Icons.inventory_2_outlined,
        color: NexHue.slate.of(theme.brightness),
      ),
      title: Text(
        MedicineModels.readString(record.body, 'name'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: TextButton(
        key: ValueKey('medicine-unarchive-${record.id}'),
        onPressed: onUnarchive,
        child: Text(medicineStrings(context, 'unarchive')),
      ),
    );
  }
}
