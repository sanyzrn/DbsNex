import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_detail_screen.dart';
import 'habit_model.dart';
import 'module.dart';
import 'store_state.dart';
import 'record_bundle.dart';

/// The archived habits: out of Today, history intact. Unarchiving is one
/// tap; anything more deliberate lives on the habit's own page.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen>
    with WidgetsBindingObserver, StoreState<ArchiveScreen> {
  List<Habit> _archived = const [];
  StreamSubscription<void>? _changes;
  int _loadToken = 0;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load() => readRecords(_read);

  Future<void> _read() async {
    await RecordBundle.recover(widget.store);
    final token = ++_loadToken;
    final habits = await widget.store.list('habit');
    if (!mounted || token != _loadToken) return;
    setState(() {
      _archived = habits.map(Habit.fromRecord).where((h) => h.archived).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  Future<void> _unarchive(Habit habit) async {
    if (_writing) return;
    setState(() => _writing = true);
    try {
      await widget.store.put(
        'habit',
        habit.id,
        habit.toJson()..['archived'] = false,
      );
    } catch (_) {
      writeError();
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: NexAppBar(title: Text(strings(context, 'archived'))),
      body: recordsBody(
        _archived.isEmpty
            ? NexEmptyState(
                icon: Icons.archive_outlined,
                message: strings(context, 'noArchived'),
              )
            : ListView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.lg + nexBottomInset(context),
                ),
                children: [
                  for (final (index, habit) in _archived.indexed)
                    NexGroupedRow(
                      index: index,
                      count: _archived.length,
                      child: ListTile(
                        onTap: () => unawaited(
                          Navigator.push(
                            context,
                            NexPageRoute<void>(
                              builder: (_) => HabitDetailScreen(
                                store: widget.store,
                                habitId: habit.id,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          habit.name.isEmpty
                              ? strings(context, 'untitled')
                              : habit.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          strings(context, 'archivedHint'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: IconButton(
                          key: ValueKey('unarchive-${habit.id}'),
                          tooltip: strings(context, 'unarchive'),
                          icon: const Icon(Icons.unarchive_outlined),
                          onPressed: _writing
                              ? null
                              : () => unawaited(_unarchive(habit)),
                        ),
                      ),
                    ),
                  const SizedBox(height: NexSpacing.xl),
                ],
              ),
        () => unawaited(_load()),
      ),
    );
  }
}
