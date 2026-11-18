import 'dart:async';

import 'local_writes.dart';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'medicine_detail.dart';
import 'medicine_editor.dart';
import 'medicine_expiry_page.dart';
import 'medicine_logic.dart';
import 'medicine_models.dart';
import 'medicine_reminders.dart';
import 'medicine_schedule.dart';
import 'medicine_settings.dart';
import 'medicine_strings.dart';
import 'medicine_today_page.dart';

part 'medicine_screen_body.dart';
part 'medicine_rows.dart';

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
  List<ModuleRecord> _boxes = const [];
  bool _showArchived = false;

  /// Null means everyone; otherwise the person's name as written.
  String? _peopleFilter;

  /// Whether this screen asked the system to keep it out of screenshots.
  bool _secure = false;
  bool _secureHeld = false;

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
    unawaited(_restoreSecure());
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
    if (_secureHeld) {
      unawaited(NexSecureWindow.releasePrivateSurface());
    }
    super.dispose();
  }

  /// The saved choice, applied before anything is painted over it: names,
  /// times and stock are health details, and keeping them out of the app
  /// switcher is a choice a person makes once.
  Future<void> _restoreSecure() async {
    final secure = await MedicineSettings.secure(widget.store);
    if (!mounted) {
      return;
    }
    if (secure) {
      final held = await NexSecureWindow.acquirePrivateSurface();
      if (!mounted) {
        return;
      }
      _secureHeld = held;
    }
    _paint(() => _secure = secure);
  }

  Future<void> _toggleSecure() async {
    final next = !_secure;
    try {
      await MedicineSettings.setSecure(widget.store, next);
      if (next) {
        _secureHeld = await NexSecureWindow.acquirePrivateSurface();
      } else if (_secureHeld) {
        await NexSecureWindow.releasePrivateSurface();
        _secureHeld = false;
      }
      if (!mounted) {
        return;
      }
      _paint(() => _secure = next);
      NexBannerHost.of(context)?.show(
        message: medicineStrings(context, next ? 'secureOn' : 'secureOff'),
      );
    } catch (_) {
      if (mounted) {
        NexBannerHost.of(context)?.show(
          kind: NexBannerKind.failed,
          message: medicineStrings(context, 'saveFailed'),
        );
      }
    }
  }

  Future<void> _openToday() async {
    await Navigator.of(context).push(
      NexPageRoute<void>(
        builder: (_) => MedicineTodayPage(store: widget.store),
      ),
    );
  }

  Future<void> _openExpiry() async {
    await Navigator.of(context).push(
      NexPageRoute<void>(
        builder: (_) => MedicineExpiryPage(store: widget.store),
      ),
    );
  }

  Future<void> _runMenu(String value) async {
    switch (value) {
      case 'expiry':
        await _openExpiry();
      case 'secure':
        await _toggleSecure();
    }
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
      // The routine's next moments are armed here, on every open and after
      // every change; the platform keeps them while the app is closed.
      unawaited(MedicineReminders.sync(context, widget.store, medicines));
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
        NexBannerHost.of(context)?.show(
          kind: NexBannerKind.failed,
          message: medicineStrings(context, 'saveFailed'),
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
