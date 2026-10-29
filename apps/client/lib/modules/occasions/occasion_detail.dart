import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'occasion_math.dart';
import 'occasion_model.dart';
import 'occasion_reminders.dart';
import 'occasion_sheet.dart';
import 'occasion_greeting.dart';
import 'occasion_text.dart';
import 'occasion_visuals.dart';

/// One occasion in full: how far away it is, the day in both calendars,
/// the age it comes to, the note, the reminder, and a greeting to copy.
/// Editing, marking, muting, archiving and deleting live here.
class OccasionDetailScreen extends StatefulWidget {
  const OccasionDetailScreen({
    super.key,
    required this.store,
    required this.occasionId,
  });

  final NexModuleStore store;
  final String occasionId;

  @override
  State<OccasionDetailScreen> createState() => _OccasionDetailScreenState();
}

class _OccasionDetailScreenState extends State<OccasionDetailScreen> {
  Occasion? _occasion;
  bool _loaded = false;
  bool _failed = false;
  bool _busy = false;
  StreamSubscription<void>? _changes;
  int _token = 0;

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
    final token = ++_token;
    try {
      final body = await widget.store.get('occasion', widget.occasionId);
      if (!mounted || token != _token) return;
      if (body == null) {
        if (!_busy) Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _occasion = Occasion.fromBody(widget.occasionId, body);
        _loaded = true;
        _failed = false;
      });
    } catch (_) {
      if (mounted && token == _token) {
        setState(() {
          _loaded = true;
          _failed = true;
        });
      }
    }
  }

  /// Writes one field change into the record as it stands now, so fields
  /// this version does not know survive, then renews the reminders.
  Future<void> _patch(Map<String, Object?> change) async {
    if (_busy || _occasion == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final failed = occasionsStrings(context, 'saveError');
    final l10n = AppLocalizations.of(context);
    try {
      final raw = await widget.store.get('occasion', widget.occasionId);
      if (raw == null) return;
      final next = {...raw, ...change};
      await widget.store.put('occasion', widget.occasionId, next);
      final occasion = Occasion.fromBody(widget.occasionId, next);
      if (!mounted) return;
      await armOccasionReminders(
        widget.store,
        occasion,
        now: DateTime.now(),
        l10n: l10n,
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final occasion = _occasion;
    if (occasion == null || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final deleted = occasionsStrings(context, 'deleted');
    final failed = occasionsStrings(context, 'saveError');
    try {
      final raw = await widget.store.get('occasion', occasion.id);
      await clearOccasionReminders(widget.store, occasion.id);
      await widget.store.delete('occasion', occasion.id);
      if (!mounted) return;
      Navigator.of(context).maybePop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(deleted),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () => unawaited(() async {
              try {
                if (raw != null) {
                  await widget.store.put('occasion', occasion.id, raw);
                  await armOccasionReminders(
                    widget.store,
                    Occasion.fromBody(occasion.id, raw),
                    now: DateTime.now(),
                    l10n: l10n,
                  );
                }
              } catch (_) {
                messenger.showSnackBar(SnackBar(content: Text(failed)));
              }
            }()),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = occasionsStrings;
    final occasion = _occasion;
    if (occasion == null) {
      return Scaffold(
        appBar: NexAppBar(),
        body: !_loaded || !_failed
            ? const Center(child: NexInlineSpinner())
            : NexEmptyState(
                icon: Icons.cloud_off_outlined,
                message: strings(context, 'loadError'),
                action: TextButton(
                  onPressed: () => unawaited(_load()),
                  child: Text(strings(context, 'retry')),
                ),
              ),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final today = DateTime.now();
    final next = nextOccasionDay(occasion, today);
    final days = next == null ? null : daysUntil(today, next.date);
    final ownSolar = occasion.calendar == OccasionCalendar.jalali;
    final title = occasion.title.isEmpty
        ? strings(context, 'untitled')
        : occasion.title;

    String reminderLine() {
      if (occasion.remindDays == null) return strings(context, 'reminderOff');
      if (occasion.muted) return strings(context, 'reminderMuted');
      final time = occasionTimeText(context, occasion.remindMinutes);
      final ahead = occasion.remindDays!;
      return ahead == 0
          ? strings(context, 'reminderOn', {
              'when': strings(context, 'reminderWhenToday'),
              'time': time,
            })
          : strings(context, 'reminderBoth', {
              'when': ahead == 1
                  ? strings(context, 'remindOneBefore')
                  : strings(context, 'reminderWhenDays', {'n': ahead}),
              'time': time,
            });
    }

    return Scaffold(
      appBar: NexAppBar(
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('occasion-edit'),
            tooltip: strings(context, 'edit'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: _busy
                ? null
                : () => unawaited(
                    showOccasionSheet(
                      context,
                      widget.store,
                      occasion: occasion,
                    ),
                  ),
          ),
          NexPopupMenuButton<String>(
            key: const ValueKey('occasion-menu'),
            tooltip: strings(context, 'more'),
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'favorite':
                  unawaited(_patch({'favorite': !occasion.favorite}));
                case 'mute':
                  unawaited(_patch({'muted': !occasion.muted}));
                case 'archive':
                  unawaited(_patch({'archived': !occasion.archived}));
                case 'delete':
                  unawaited(_delete());
              }
            },
            itemBuilder: (context) => [
              nexMenuItem(
                value: 'favorite',
                icon: Icons.star_outline,
                label: strings(
                  context,
                  occasion.favorite ? 'unfavorite' : 'favorite',
                ),
              ),
              nexMenuItem(
                value: 'mute',
                icon: Icons.notifications_off_outlined,
                label: strings(context, occasion.muted ? 'unmute' : 'mute'),
              ),
              nexMenuItem(
                value: 'archive',
                icon: Icons.archive_outlined,
                label: strings(
                  context,
                  occasion.archived ? 'unarchive' : 'archive',
                ),
              ),
              nexMenuItem(
                value: 'delete',
                icon: Icons.delete_outline,
                label: strings(context, 'delete'),
                destructive: true,
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsetsDirectional.fromSTEB(
          NexSpacing.md,
          NexSpacing.sm,
          NexSpacing.md,
          NexSpacing.lg + nexBottomInset(context),
        ),
        children: [
          if (next != null)
            OccasionHeroCard(
              occasion: occasion,
              next: next,
              today: today,
              eyebrow: [
                occasionKindLabel(context, occasion.kind),
                if (occasion.favorite) '★',
              ].join(' '),
              actions: days == 0 && occasion.kind != OccasionKind.memorial
                  ? OccasionGreetingActions(occasion: occasion)
                  : null,
            )
          else
            NexPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings(context, 'invalidTitle'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  Text(
                    strings(context, 'fixDate'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          if (next != null) ...[
            const SizedBox(height: NexSpacing.md),
            NexPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _CalendarDay(
                          label: strings(context, 'jalali'),
                          text: occasionDateText(
                            context,
                            next.date,
                            solar: true,
                          ),
                          own: ownSolar,
                        ),
                      ),
                      const SizedBox(width: NexSpacing.sm),
                      Expanded(
                        child: _CalendarDay(
                          label: strings(context, 'gregorian'),
                          text: occasionDateText(
                            context,
                            next.date,
                            solar: false,
                          ),
                          own: !ownSolar,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  Text(
                    strings(context, 'repeatsOn', {
                      'date': nexDigits(
                        '${occasion.day} ${nexModuleMonthName(context, solar: ownSolar, month: occasion.month)}',
                        persian: persian,
                      ),
                      'calendar': strings(
                        context,
                        ownSolar ? 'jalali' : 'gregorian',
                      ),
                    }),
                    key: const ValueKey('occasion-both-calendars'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Divider(height: NexSpacing.lg),
                  Row(
                    children: [
                      Icon(
                        occasion.remindDays == null || occasion.muted
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_active_outlined,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: NexSpacing.sm),
                      Expanded(
                        child: Text(
                          reminderLine(),
                          key: const ValueKey('occasion-reminder-line'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (occasion.note.trim().isNotEmpty) ...[
            const SizedBox(height: NexSpacing.md),
            NexPanel(
              icon: Icons.notes_outlined,
              child: NexTextSurface(occasion.note, selectable: true),
            ),
          ],
          const SizedBox(height: NexSpacing.md),
          OccasionGreetingPanel(occasion: occasion),
        ],
      ),
    );
  }
}

/// One of the two calendars an occasion's next day is shown in; the one it
/// is kept in is marked.
class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.label,
    required this.text,
    required this.own,
  });

  final String label;
  final String text;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: own ? scheme.primary.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(NexRadius.md),
        border: Border.all(
          color: own
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NexSpacing.sm + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: own ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(text, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
