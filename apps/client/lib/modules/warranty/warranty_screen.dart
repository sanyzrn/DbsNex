import 'dart:async';
import 'local_writes.dart';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'warranty_detail.dart';
import 'warranty_editor.dart';
import 'warranty_logic.dart';
import 'warranty_models.dart';
import 'warranty_strings.dart';
import 'warranty_widgets.dart';

part 'warranty_screen_body.dart';

/// The main screen: **Covered**, **Ending soon** and **Expired**, decided
/// on every view from real dates — with search by product or brand, an
/// optional soonest-end sort, and archived purchases behind a toggle.
/// Nothing is scheduled: a coverage that ends while the app is closed is
/// simply shown as expired the next time the list is read.
class WarrantyScreen extends StatefulWidget {
  const WarrantyScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<WarrantyScreen> createState() => _WarrantyScreenState();
}

class _WarrantyScreenState extends State<WarrantyScreen>
    with WidgetsBindingObserver {
  List<ModuleRecord> _warranties = const [];
  bool _sortSoonest = false;
  bool _showArchived = false;
  bool _searching = false;
  final _query = TextEditingController();

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
    _query.addListener(_onQuery);
    unawaited(_load());
  }

  void _onQuery() {
    if (mounted) {
      setState(() {});
    }
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
    _query.removeListener(_onQuery);
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    try {
      await LocalWrites.recover(widget.store);

      final warranties = await widget.store.list(WarrantyModels.warranty);
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _warranties = warranties;
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
        builder: (_) => WarrantyEditorSheet(store: widget.store),
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
      builder: (_) => WarrantyDetailSheet(store: widget.store, record: record),
    );
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

  void _paint(VoidCallback change) {
    if (mounted) {
      setState(change);
    }
  }

  @override
  Widget build(BuildContext context) => _view(context);
}

/// The search line, drawn like the app's other fields: it follows the
/// script being typed, so a Persian query reads from the right the way
/// the rest of the app does.
class WarrantyFieldsLine extends StatelessWidget {
  const WarrantyFieldsLine({super.key, required this.controller, this.label});

  final TextEditingController controller;
  final String? label;

  @override
  Widget build(BuildContext context) => NexAutoDirection(
    controller: controller,
    builder: (context, direction) => TextField(
      key: const ValueKey('warranty-field-search'),
      controller: controller,
      textDirection: direction,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.search),
      ),
    ),
  );
}
