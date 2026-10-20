import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'occasion_detail.dart';
import 'occasion_math.dart';
import 'occasion_model.dart';
import 'occasion_reminders.dart';
import 'occasion_row.dart';
import 'occasion_sheet.dart';
import 'occasion_text.dart';

/// The list: what falls today, in the next week, in the next month and
/// later, nearest first. A date that cannot be worked out is listed apart so
/// it can be fixed, never given a guess.
class OccasionsScreen extends StatefulWidget {
  const OccasionsScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<OccasionsScreen> createState() => _OccasionsScreenState();
}

class _OccasionsScreenState extends State<OccasionsScreen>
    with WidgetsBindingObserver {
  List<Occasion> _items = const [];
  bool _loading = true;
  bool _failed = false;
  bool _showArchived = false;
  bool _renewed = false;
  int _token = 0;
  StreamSubscription<void>? _changes;

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

  Future<void> _load() async {
    final token = ++_token;
    try {
      final records = await widget.store.list('occasion');
      if (!mounted || token != _token) return;
      setState(() {
        _items = records.map(Occasion.fromRecord).toList();
        _loading = false;
        _failed = false;
      });
      if (!_renewed) {
        _renewed = true;
        unawaited(_renewReminders());
      }
    } catch (_) {
      if (mounted && token == _token) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  /// Once per visit: the two alarms an occasion keeps ahead are made again,
  /// so a date that was opened lately keeps ringing. Quiet — a failure here
  /// is not the person's doing and nothing was just asked of them.
  Future<void> _renewReminders() async {
    final title = AppLocalizations.of(context).cycleNotifyTitle;
    for (final occasion in _items) {
      if (occasion.remindDays == null || occasion.muted || occasion.archived) {
        continue;
      }
      if (!mounted) return;
      try {
        await armOccasionReminders(
          widget.store,
          occasion,
          now: DateTime.now(),
          title: title,
          body: occasionNotificationBody(context, occasion),
        );
      } catch (_) {
        /* The next visit tries again. */
      }
    }
  }

  Future<void> _add() => showOccasionSheet(context, widget.store);

  void _open(Occasion occasion) => unawaited(
    Navigator.push(
      context,
      NexPageRoute<void>(
        builder: (_) =>
            OccasionDetailScreen(store: widget.store, occasionId: occasion.id),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = occasionsStrings;
    final today = DateTime.now();
    final active = _items.where((o) => !o.archived).toList();
    final archived = _items.where((o) => o.archived).toList();

    // Each active occasion with its next day; nearest first, important ones
    // ahead of the rest on the same day.
    final dated = <(Occasion, OccasionDay)>[];
    final undated = <Occasion>[];
    for (final occasion in active) {
      final next = nextOccasionDay(occasion, today);
      if (next == null) {
        undated.add(occasion);
      } else {
        dated.add((occasion, next));
      }
    }
    dated.sort((a, b) {
      final byDate = a.$2.date.compareTo(b.$2.date);
      if (byDate != 0) return byDate;
      if (a.$1.favorite != b.$1.favorite) return a.$1.favorite ? -1 : 1;
      return a.$1.title.compareTo(b.$1.title);
    });
    List<(Occasion, OccasionDay)> within(int from, int to) => [
      for (final entry in dated)
        if (daysUntil(today, entry.$2.date) >= from &&
            daysUntil(today, entry.$2.date) <= to)
          entry,
    ];
    final sections = <(String, List<(Occasion, OccasionDay)>)>[
      ('sectionToday', within(0, 0)),
      ('sectionWeek', within(1, 7)),
      ('sectionMonth', within(8, 30)),
      ('sectionLater', within(31, 1 << 30)),
    ];

    Widget list(List<(Occasion, OccasionDay?)> rows) => Column(
      children: [
        for (final (index, row) in rows.indexed)
          OccasionRow(
            index: index,
            count: rows.length,
            occasion: row.$1,
            next: row.$2,
            today: today,
            onOpen: () => _open(row.$1),
          ),
      ],
    );

    final body = _loading
        ? const Center(child: NexInlineSpinner())
        : _failed
        ? NexEmptyState(
            icon: Icons.cloud_off_outlined,
            message: strings(context, 'loadError'),
            action: TextButton(
              onPressed: () => unawaited(_load()),
              child: Text(strings(context, 'retry')),
            ),
          )
        : _items.isEmpty
        ? LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: NexEmptyState(
                  icon: Icons.cake_outlined,
                  message: strings(context, 'empty'),
                  action: FilledButton.icon(
                    key: const ValueKey('occasions-add'),
                    onPressed: () => unawaited(_add()),
                    icon: const Icon(Icons.add),
                    label: Text(strings(context, 'add')),
                  ),
                ),
              ),
            ),
          )
        : ListView(
            padding: EdgeInsetsDirectional.fromSTEB(
              NexSpacing.md,
              NexSpacing.sm,
              NexSpacing.md,
              NexSpacing.xl * 3 + nexBottomInset(context),
            ),
            children: [
              for (final (key, rows) in sections)
                if (rows.isNotEmpty) ...[
                  NexShelfHeading(
                    icon: key == 'sectionToday'
                        ? Icons.today_outlined
                        : Icons.event_outlined,
                    title: strings(context, key),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  list([for (final (o, d) in rows) (o, d)]),
                  const SizedBox(height: NexSpacing.md),
                ],
              if (undated.isNotEmpty) ...[
                NexShelfHeading(
                  icon: Icons.edit_calendar_outlined,
                  title: strings(context, 'sectionFix'),
                ),
                const SizedBox(height: NexSpacing.sm),
                list([for (final o in undated) (o, null)]),
                const SizedBox(height: NexSpacing.md),
              ],
              if (archived.isNotEmpty) ...[
                TextButton.icon(
                  key: const ValueKey('occasions-archived-toggle'),
                  onPressed: () =>
                      setState(() => _showArchived = !_showArchived),
                  icon: Icon(
                    _showArchived ? Icons.expand_less : Icons.archive_outlined,
                  ),
                  label: Text(
                    _showArchived
                        ? strings(context, 'hideArchived')
                        : strings(context, 'showArchived', {
                            'n': archived.length,
                          }),
                  ),
                ),
                if (_showArchived)
                  list([
                    for (final o in archived) (o, nextOccasionDay(o, today)),
                  ]),
              ],
            ],
          );

    return Scaffold(
      appBar: NexAppBar(title: Text(strings(context, 'title'))),
      // One primary action per page: with nothing yet, it is the button in
      // the empty state, not a second one floating beside it.
      floatingActionButton: _items.isEmpty || _loading || _failed
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('occasions-add'),
              onPressed: () => unawaited(_add()),
              icon: const Icon(Icons.add),
              label: Text(strings(context, 'add')),
            ),
      body: body,
    );
  }
}
