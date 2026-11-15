import 'dart:async';

import 'local_writes.dart';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'warranty_dialogs.dart';
import 'warranty_editor.dart';
import 'warranty_fields.dart';
import 'warranty_logic.dart';
import 'warranty_service_file.dart';
import 'warranty_models.dart';
import 'warranty_strings.dart';
import 'warranty_widgets.dart';

part 'warranty_detail_body.dart';
part 'warranty_detail_status.dart';

/// One purchase, in full: what it is, who covers it and how to reach them,
/// the card and serial, the coverage period, the amount as paid, and the
/// claim and service notes under it — each dated, each manual.
///
/// This is a page rather than a sheet: it holds a whole record, its own
/// notes and its own actions, and it is read while a service desk is
/// talking, when a back gesture and a fixed app bar help.
class WarrantyDetailPage extends StatefulWidget {
  const WarrantyDetailPage({
    super.key,
    required this.store,
    required this.record,
    this.inSheet = false,
  });

  final NexModuleStore store;

  /// Drawn without its own app bar, for the one caller that still opens a
  /// purchase inside a sheet: the notification destination in the app's own
  /// route resolver, which the module may not change. Everything else opens
  /// the page.
  final bool inSheet;

  /// The row that was tapped; its id is what the page loads fresh, so a
  /// record changed elsewhere is never shown stale.
  final ModuleRecord record;

  @override
  State<WarrantyDetailPage> createState() => _WarrantyDetailPageState();
}

class _WarrantyDetailPageState extends State<WarrantyDetailPage> {
  Map<String, Object?>? _body;
  List<ModuleRecord> _claims = const [];
  StreamSubscription<void>? _changes;
  int _loadSeq = 0;
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;

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
        NexBannerHost.of(context),
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
      case 'copyFile':
        await _copyFile();
      case 'shareFile':
        await nexModuleShareText(warrantyServiceFile(context, _body!, _claims));
    }
  }

  /// The service file on the clipboard — a hand-over, never sent anywhere
  /// by the module itself.
  Future<void> _copyFile() async {
    if (_body == null) return;
    await nexModuleCopyText(warrantyServiceFile(context, _body!, _claims));
    if (!mounted) return;
    nexShowBanner(context, message: warrantyStrings(context, 'fileCopied'));
  }

  Future<void> _copyPhone(String phone) async {
    await nexModuleCopyText(phone);
    if (!mounted) return;
    nexShowBanner(context, message: warrantyStrings(context, 'phoneCopied'));
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

  /// Archives this purchase, with Undo shown by the page behind it.
  Future<void> _archive() async {
    await _work(() async {
      await LocalWrites.patch(
        widget.store,
        WarrantyModels.warranty,
        widget.record.id,
        {'archived': true},
      );
      if (!mounted) return;
      final messenger = NexBannerHost.of(context);
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
      if (!mounted) return;
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
      if (!mounted) return;
      WarrantyDialogs.offerUndo(
        NexBannerHost.of(context),
        warrantyStrings(context, 'warrantyDeleted'),
        AppLocalizations.of(context).undo,
        undo,
      );
      Navigator.of(context).pop();
    });
  }

  // -------------------------------------------------------------- build

  Future<void> _work(Future<void> Function() run) async {
    if (_busy || _loading || _loadFailed) {
      return;
    }
    setState(() => _busy = true);
    try {
      await run();
    } catch (_) {
      if (mounted) {
        NexBannerHost.of(context)?.show(
          kind: NexBannerKind.failed,
          message: warrantyStrings(context, 'saveFailed'),
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

/// The entry point the app's notification resolver uses: a purchase opened
/// from a reminder, inside the sheet that resolver builds. It is the same
/// widget and the same record as [WarrantyDetailPage], without the app bar
/// the surrounding sheet already stands in for.
class WarrantyDetailSheet extends WarrantyDetailPage {
  const WarrantyDetailSheet({
    super.key,
    required super.store,
    required super.record,
  }) : super(inSheet: true);
}
