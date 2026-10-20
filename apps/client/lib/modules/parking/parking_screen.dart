import 'dart:async';
import 'local_writes.dart';
import 'parking_repository.dart';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'parking_detail.dart';
import 'parking_dialogs.dart';
import 'parking_editor.dart';
import 'parking_fields.dart';
import 'parking_logic.dart';
import 'parking_models.dart';
import 'parking_strings.dart';
import 'parking_widgets.dart';
import 'parking_writes.dart';

part 'parking_screen_body.dart';

/// The module's one screen: the open parking at the top where the eye
/// lands first, the places this person parks often under it, and the
/// closed history below.
///
/// A timer refreshes the elapsed and remaining times **while the screen is
/// open** — a foreground look at the clock, not a background job. A person
/// who wants to be told after closing the app sets the explicit, opt-in
/// device reminder offered on the open parking (the platform schedules it
/// and auto-cancels it when the record goes away).
class ParkingScreen extends StatefulWidget {
  const ParkingScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<ParkingScreen> createState() => _ParkingScreenState();
}

class _ParkingScreenState extends State<ParkingScreen>
    with WidgetsBindingObserver {
  List<ModuleRecord> _sessions = const [];
  List<ModuleRecord> _places = const [];
  List<ModuleRecord> _queries = const [];
  StreamSubscription<void>? _changes;
  Timer? _tick;

  /// A load in flight is newer than one that has not started, so a slow
  /// earlier read cannot repaint over a later one.
  int _loadSeq = 0;
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;

  bool _searching = false;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    _query.addListener(_onQuery);
    unawaited(_load());
    _startTick();
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          _sessions.any((r) => ParkingLogic.isActive(r.body))) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
      _startTick();
    } else {
      _tick?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    _tick?.cancel();
    _query.removeListener(_onQuery);
    _query.dispose();
    super.dispose();
  }

  /// The list follows the search field as it is typed.
  void _onQuery() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    try {
      await LocalWrites.recover(widget.store);

      final sessions = await widget.store.list(ParkingModels.session);
      final places = await widget.store.list(ParkingModels.place);
      final queries = await widget.store.list(ParkingModels.search);
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _loading = false;
        _loadFailed = false;
        _sessions = sessions;
        _places = places;
        _queries = queries;
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

  // ----------------------------------------------------------- openings

  Future<void> _newParking([ModuleRecord? place]) async {
    if (_busy || _loading || _loadFailed) {
      return;
    }
    setState(() => _busy = true);
    try {
      await nexShowSheet<void>(
        context: context,
        dismissible: false,
        swipeToClose: true,
        builder: (_) =>
            ParkingEditorSheet(store: widget.store, place: place?.body),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _editParking(ModuleRecord record) async {
    if (_busy || _loading || _loadFailed) {
      return;
    }
    setState(() => _busy = true);
    try {
      await nexShowSheet<void>(
        context: context,
        dismissible: false,
        swipeToClose: true,
        builder: (_) =>
            ParkingEditorSheet(store: widget.store, existing: record),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // -------------------------------------------------------------- saving

  /// Writes a draft, asking about an earlier open parking for the same
  /// vehicle first — the question exists so an old entry is *closed* or
  /// *kept*, never deleted in silence.

  // ------------------------------------------------------------ changes

  Future<void> _foundCar(ModuleRecord record) async {
    await _work(() => ParkingRepository.found(widget.store, record.id));
  }

  /// Deletes one record and offers Undo. The body is captured before the
  /// delete, so restoring puts back exactly what was there.
  Future<void> _delete(ModuleRecord record) async {
    if (_busy) {
      return;
    }
    if (await ParkingDialogs.confirmDelete(context, parkingStrings) != true ||
        !mounted) {
      return;
    }
    await _work(() async {
      final undo = await ParkingRepository.delete(widget.store, record.id);
      if (!mounted) {
        return;
      }
      ParkingDialogs.offerUndo(
        ScaffoldMessenger.of(context),
        parkingStrings(context, 'deletedOne'),
        AppLocalizations.of(context).undo,
        undo,
      );
    });
  }

  /// Deletes every closed parking at once, with one Undo for the lot.
  Future<void> _clearHistory() async {
    if (_busy) {
      return;
    }
    if (await ParkingDialogs.confirmClearHistory(context, parkingStrings) !=
            true ||
        !mounted) {
      return;
    }
    await _work(() async {
      final undo = await LocalWrites.serial(widget.store, () async {
        final closed = (await widget.store.list(
          ParkingModels.session,
        )).where((r) => !ParkingLogic.isActive(r.body));
        return LocalWrites.apply(widget.store, [
          for (final r in closed) ...[
            (kind: 'draft', id: 'session:${r.id}', body: null),
            (kind: ParkingModels.session, id: r.id, body: null),
          ],
        ]);
      });
      if (!mounted) {
        return;
      }
      ParkingDialogs.offerUndo(
        ScaffoldMessenger.of(context),
        parkingStrings(context, 'clearedHistory'),
        AppLocalizations.of(context).undo,
        undo,
      );
    });
  }

  // -------------------------------------------------------------- build

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

  void _paint(VoidCallback change) {
    if (mounted) {
      setState(change);
    }
  }

  @override
  Widget build(BuildContext context) => _view(context);
}
