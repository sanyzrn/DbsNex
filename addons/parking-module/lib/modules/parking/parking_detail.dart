import 'dart:async';
import 'local_writes.dart';
import 'parking_repository.dart';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'parking_dialogs.dart';
import 'parking_editor.dart';
import 'parking_fields.dart';
import 'parking_logic.dart';
import 'parking_models.dart';
import 'parking_strings.dart';

part 'parking_detail_body.dart';

/// One parking, in full: every field the person wrote, when it started
/// and ended, and what it adds up to. Editing happens through the same
/// sheet as a new parking; deleting offers Undo.
class ParkingDetailPage extends StatefulWidget {
  const ParkingDetailPage({
    super.key,
    required this.store,
    required this.sessionId,
  });

  final NexModuleStore store;
  final String sessionId;

  @override
  State<ParkingDetailPage> createState() => _ParkingDetailPageState();
}

class _ParkingDetailPageState extends State<ParkingDetailPage> {
  Map<String, Object?>? _body;
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
        ParkingModels.session,
        widget.sessionId,
      );
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _body = body;
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

  Future<void> _edit() async {
    if (_body == null || _busy || _loadFailed) {
      return;
    }
    await nexShowSheet<void>(
      context: context,
      dismissible: false,
      swipeToClose: true,
      builder: (_) => ParkingEditorSheet(
        store: widget.store,
        existing: ModuleRecord(
          module: 'parking',
          kind: ParkingModels.session,
          id: widget.sessionId,
          body: _body!,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> _found() async {
    await _work(() => ParkingRepository.found(widget.store, widget.sessionId));
  }

  Future<void> _delete() async {
    if (_busy || _body == null) {
      return;
    }
    if (await ParkingDialogs.confirmDelete(context, parkingStrings) != true ||
        !mounted) {
      return;
    }
    await _work(() async {
      final undo = await ParkingRepository.delete(
        widget.store,
        widget.sessionId,
      );
      if (!mounted) {
        return;
      }
      ParkingDialogs.offerUndo(
        ScaffoldMessenger.of(context),
        parkingStrings(context, 'deletedOne'),
        AppLocalizations.of(context).undo,
        undo,
      );
      unawaited(Navigator.of(context).maybePop());
    });
  }

  Widget _readError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(parkingStrings(context, 'loadFailed')),
          TextButton(
            onPressed: () => unawaited(_load()),
            child: Text(parkingStrings(context, 'retry')),
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
          SnackBar(content: Text(parkingStrings(context, 'saveFailed'))),
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
