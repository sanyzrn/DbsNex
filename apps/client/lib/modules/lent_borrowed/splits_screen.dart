import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_date_entry.dart';
import 'loan_settings.dart';
import 'money_format.dart';
import 'split_detail_screen.dart';
import 'split_editor_sheet.dart';
import 'split_model.dart';
import 'store_state.dart';
import 'upgrade_strings.dart';

/// Every split — a trip, a shared month, a party — with its total and how
/// many people share it. Opening one shows who pays whom.
class SplitsScreen extends StatefulWidget {
  const SplitsScreen({super.key, required this.store, this.unit});

  final NexModuleStore store;
  final IrrUnit? unit;

  @override
  State<SplitsScreen> createState() => _SplitsScreenState();
}

class _SplitsScreenState extends State<SplitsScreen>
    with StoreState<SplitsScreen> {
  List<LoanSplit> _splits = const [];
  late IrrUnit _unit = widget.unit ?? IrrUnit.toman;
  StreamSubscription<void>? _changes;
  bool _editorOpen = false;

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

  Future<void> _load() => readRecords(() async {
    final settings = await readLoanSettings(widget.store);
    final records = await widget.store.list('split');
    if (!mounted) return;
    setState(() {
      _unit = settings.irrUnit;
      _splits = records.map(LoanSplit.fromRecord).toList()
        ..sort((a, b) {
          final byDate = b.date.compareTo(a.date);
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        });
    });
  });

  Future<void> _add() async {
    if (_editorOpen) return;
    _editorOpen = true;
    try {
      final saved = await showSplitEditorSheet(
        context,
        widget.store,
        unit: _unit,
      );
      if (saved == true && mounted) await _load();
    } finally {
      _editorOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final persian = NexModuleStrings.persian(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: NexAppBar(title: Text(strings(context, 'splitsTitle'))),
      floatingActionButton: _splits.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              key: const ValueKey('splits-new'),
              onPressed: () => unawaited(_add()),
              icon: const Icon(Icons.add),
              label: Text(strings(context, 'splitNew')),
            ),
      body: recordsBody(
        _splits.isEmpty
            ? NexEmptyState(
                icon: Icons.groups_outlined,
                message: strings(context, 'splitsEmpty'),
                action: TextButton(
                  key: const ValueKey('splits-empty-add'),
                  onPressed: () => unawaited(_add()),
                  child: Text(strings(context, 'splitNew')),
                ),
              )
            : ListView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.lg + nexBottomInset(context),
                ),
                children: [
                  for (final (index, split) in _splits.indexed)
                    NexGroupedRow(
                      index: index,
                      count: _splits.length,
                      child: ListTile(
                        key: ValueKey('split-${split.id}'),
                        onTap: () => unawaited(
                          Navigator.push(
                            context,
                            NexPageRoute<void>(
                              builder: (_) => SplitDetailScreen(
                                store: widget.store,
                                splitId: split.id,
                                unit: _unit,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          split.title.isEmpty
                              ? strings(context, 'splitsTitle')
                              : split.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Text(
                          '${loanDateLabel(context, split.date)} · '
                          '${formatAmount(split.total, 'IRR', 0, persian, _unit)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                ],
              ),
        () => unawaited(_load()),
      ),
    );
  }
}
