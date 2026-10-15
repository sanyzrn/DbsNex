import 'dart:async';
import 'local_writes.dart';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'warranty_dialogs.dart';
import 'warranty_editor.dart';
import 'warranty_fields.dart';
import 'warranty_models.dart';
import 'warranty_strings.dart';
import 'warranty_widgets.dart';

part 'warranty_detail_body.dart';

/// One purchase, in full: everything the person wrote, the coverage
/// period, the amount in rials or tomans as they choose to read it, and
/// the claim and service notes under it — each dated, each manual.
class WarrantyDetailSheet extends StatefulWidget {
  const WarrantyDetailSheet({
    super.key,
    required this.store,
    required this.record,
  });

  final NexModuleStore store;
  final ModuleRecord record;

  @override
  State<WarrantyDetailSheet> createState() => _WarrantyDetailSheetState();
}

class _WarrantyDetailSheetState extends State<WarrantyDetailSheet> {
  Map<String, Object?>? _body;
  List<ModuleRecord> _claims = const [];
  StreamSubscription<void>? _changes;
  int _loadSeq = 0;
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;

  /// The messenger inside the sheet, where its own snackbars belong.
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
        WarrantyModels.warranty,
        widget.record.id,
      );
      final claims = await widget.store.list(WarrantyModels.claim);
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _loading = false;
        _loadFailed = false;
        _body = body;
        _claims = [
          for (final claim in claims)
            if (WarrantyModels.readString(claim.body, 'warrantyId') ==
                widget.record.id)
              claim,
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

  // -------------------------------------------------------------- claims

  /// Adds a dated claim or service note, in the person's own words. No
  /// outcome is presumed, and nothing is sent to anyone.
  Future<void> _addClaim(String kind) async {
    if (_body == null || _busy || _loadFailed) {
      return;
    }
    await nexShowSheet<void>(
      context: context,
      dismissible: false,
      swipeToClose: true,
      builder: (_) => WarrantyClaimSheet(
        store: widget.store,
        parentId: widget.record.id,
        kind: kind,
      ),
    );
  }

  Future<void> _deleteClaim(ModuleRecord claim) async {
    await _work(() async {
      final undo = await LocalWrites.delete(
        widget.store,
        WarrantyModels.claim,
        claim.id,
      );
      if (!mounted) {
        return;
      }
      WarrantyDialogs.offerUndo(
        _messenger(),
        warrantyStrings(context, 'claimDeleted'),
        AppLocalizations.of(context).undo,
        undo,
      );
    });
  }

  // ------------------------------------------------------------- actions

  Future<void> _runAction(String value) async {
    switch (value) {
      case 'edit':
        await _edit();
      case 'archive':
        await _archive();
      case 'unarchive':
        await _unarchive();
      case 'delete':
        await _delete();
    }
  }

  Future<void> _edit() async {
    if (_body == null || _busy || _loadFailed) {
      return;
    }
    await nexShowSheet<void>(
      context: context,
      dismissible: false,
      swipeToClose: true,
      builder: (_) => WarrantyEditorSheet(
        store: widget.store,
        existing: ModuleRecord(
          module: 'warranty',
          kind: WarrantyModels.warranty,
          id: widget.record.id,
          body: _body!,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  /// Archives this purchase, with Undo shown by the screen behind it.
  Future<void> _archive() async {
    await _work(() async {
      await LocalWrites.patch(
        widget.store,
        WarrantyModels.warranty,
        widget.record.id,
        {'archived': true},
      );
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      final undo = AppLocalizations.of(context).undo;
      WarrantyDialogs.offerUndo(
        messenger,
        warrantyStrings(context, 'warrantyArchived'),
        undo,
        () => LocalWrites.patch(
          widget.store,
          WarrantyModels.warranty,
          widget.record.id,
          {'archived': false},
        ),
      );
      Navigator.of(context).pop();
    });
  }

  Future<void> _unarchive() async {
    await _work(() async {
      await LocalWrites.patch(
        widget.store,
        WarrantyModels.warranty,
        widget.record.id,
        {'archived': false},
      );
      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    });
  }

  /// Deletes this purchase and its claim notes together, with one Undo
  /// that brings the whole set back exactly as it was.
  Future<void> _delete() async {
    if (_busy || _body == null) {
      return;
    }
    if (await WarrantyDialogs.confirmDelete(
              context,
              warrantyStrings,
              WarrantyModels.readString(_body ?? {}, 'product'),
            ) !=
            true ||
        !mounted) {
      return;
    }
    await _work(() async {
      final undo = await LocalWrites.delete(
        widget.store,
        WarrantyModels.warranty,
        widget.record.id,
        children: WarrantyModels.claim,
        parentField: 'warrantyId',
      );
      if (!mounted) {
        return;
      }
      WarrantyDialogs.offerUndo(
        ScaffoldMessenger.of(context),
        warrantyStrings(context, 'warrantyDeleted'),
        AppLocalizations.of(context).undo,
        undo,
      );
      Navigator.of(context).pop();
    });
  }

  // -------------------------------------------------------------- build

  Widget _readError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(warrantyStrings(context, 'loadFailed')),
          TextButton(
            onPressed: () => unawaited(_load()),
            child: Text(warrantyStrings(context, 'retry')),
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
          SnackBar(content: Text(warrantyStrings(context, 'saveFailed'))),
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
