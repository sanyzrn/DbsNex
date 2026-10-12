import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';

class TallyScreen extends StatefulWidget {
  const TallyScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<TallyScreen> createState() => _TallyScreenState();
}

class _TallyScreenState extends State<TallyScreen> {
  List<ModuleRecord> _taps = const [];
  StreamSubscription<void>? _changes;

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
    final taps = await widget.store.list('tap');
    if (mounted) setState(() => _taps = taps);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tallyStrings(context, 'title'))),
    body: Padding(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Text(
        tallyStrings(context, 'count', {'count': _taps.length}),
        key: const ValueKey('tally-count'),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      key: const ValueKey('tally-add'),
      onPressed: () => unawaited(
        widget.store.put('tap', widget.store.newId(), {
          'at': DateTime.now().toIso8601String(),
        }),
      ),
      label: Text(tallyStrings(context, 'add')),
    ),
  );
}
