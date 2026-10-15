import 'dart:async';
import 'local_writes.dart';
import 'medicine_repository.dart';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'medicine_dialogs.dart';
import 'medicine_editor.dart';
import 'medicine_models.dart';
import 'medicine_strings.dart';
import 'medicine_widgets.dart';

part 'medicine_detail_body.dart';

/// One medicine, in full: everything the person wrote about it, the doses
/// they logged, and the two log actions — «Taken» and «Skipped» — tied to
/// a time and to this medicine. Nothing here is inferred: a dose not
/// logged is not a dose missed, and the routine times are reference only.
class MedicineDetailSheet extends StatefulWidget {
  const MedicineDetailSheet({
    super.key,
    required this.store,
    required this.record,
  });

  final NexModuleStore store;
  final ModuleRecord record;

  @override
  State<MedicineDetailSheet> createState() => _MedicineDetailSheetState();
}

class _MedicineDetailSheetState extends State<MedicineDetailSheet> {
  List<ModuleRecord> _doses = const [];
  Map<String, Object?>? _body;
  StreamSubscription<void>? _changes;
  int _loadSeq = 0;
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;

  /// The messenger inside the sheet, where its own snackbars belong —
  /// captured during build, below the nested ScaffoldMessenger.
  ScaffoldMessengerState? _sheetMessenger;

  ScaffoldMessengerState _messenger() =>
      _sheetMessenger ?? ScaffoldMessenger.of(context);

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

      final body = await widget.store.get(
        MedicineModels.medicine,
        widget.record.id,
      );
      final doses = await widget.store.list(MedicineModels.dose);
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _loading = false;
        _loadFailed = false;
        _body = body;
        _doses = [
          for (final dose in doses)
            if (MedicineModels.readString(dose.body, 'medicineId') ==
                widget.record.id)
              dose,
        ];
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

  // -------------------------------------------------------- log actions

  /// Writes one dose log. When the medicine says, in the person's own
  /// numbers, how many units a dose uses, stock falls by exactly that —
  /// never by anything guessed.
  Future<void> _log(String action) async {
    await _work(
      () => MedicineRepository.log(widget.store, widget.record.id, action),
    );
  }

  /// Deletes one dose log as a correction. Stock the log took comes back;
  /// Undo puts the log — and the stock — as they were.
  Future<void> _deleteDose(ModuleRecord dose) async {
    await _work(() async {
      final undo = await MedicineRepository.deleteDose(
        widget.store,
        widget.record.id,
        dose.id,
      );
      if (!mounted) {
        return;
      }
      MedicineDialogs.offerUndo(
        _messenger(),
        medicineStrings(context, 'doseDeleted'),
        AppLocalizations.of(context).undo,
        undo,
      );
    });
  }

  Future<void> _edit() async {
    if (_body == null || _busy || _loadFailed) {
      return;
    }
    await nexShowSheet<void>(
      context: context,
      dismissible: false,
      swipeToClose: true,
      builder: (_) => MedicineEditorSheet(
        store: widget.store,
        existing: ModuleRecord(
          module: 'medicine',
          kind: MedicineModels.medicine,
          id: widget.record.id,
          body: _body!,
          updatedAt: DateTime.now(),
        ),
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

  @override
  Widget build(BuildContext context) => _view(context);
}
