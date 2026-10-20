import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'occasion_math.dart';
import 'occasion_model.dart';
import 'occasion_reminders.dart';
import 'occasion_sheet.dart';
import 'occasion_text.dart';

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
      final body = occasionNotificationBody(context, occasion);
      await armOccasionReminders(
        widget.store,
        occasion,
        now: DateTime.now(),
        title: l10n.cycleNotifyTitle,
        body: body,
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
    final title = l10n.cycleNotifyTitle;
    final body = occasionNotificationBody(context, occasion);
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
                    title: title,
                    body: body,
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
    final years = next == null ? null : yearsText(context, occasion, next);
    final ownSolar = occasion.calendar == OccasionCalendar.jalali;
    final title = occasion.title.isEmpty
        ? strings(context, 'untitled')
        : occasion.title;

    String reminderLine() {
      if (occasion.remindDays == null) return strings(context, 'reminderOff');
      if (occasion.muted) return strings(context, 'reminderMuted');
      return strings(context, 'reminderOn', {
        'when': occasion.remindDays == 0
            ? strings(context, 'reminderWhenToday')
            : occasion.remindDays == 1
            ? strings(context, 'remindOneBefore')
            : strings(context, 'reminderWhenDays', {'n': occasion.remindDays}),
        'time': occasionTimeText(context, occasion.remindMinutes),
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
              PopupMenuItem(
                value: 'favorite',
                child: Text(
                  strings(
                    context,
                    occasion.favorite ? 'unfavorite' : 'favorite',
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'mute',
                child: Text(
                  strings(context, occasion.muted ? 'unmute' : 'mute'),
                ),
              ),
              PopupMenuItem(
                value: 'archive',
                child: Text(
                  strings(context, occasion.archived ? 'unarchive' : 'archive'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  strings(context, 'delete'),
                  style: TextStyle(color: scheme.error),
                ),
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
          NexPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    NexIconTile(
                      occasionIcon(occasion.kind),
                      color: NexHue.rose.of(theme.brightness),
                    ),
                    const SizedBox(width: NexSpacing.md),
                    Expanded(
                      child: Text(
                        occasionKindLabel(context, occasion.kind),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    if (occasion.favorite)
                      Icon(Icons.star_rounded, color: scheme.primary),
                  ],
                ),
                const SizedBox(height: NexSpacing.md),
                if (days != null)
                  Text(
                    countdownText(context, days),
                    key: const ValueKey('occasion-countdown'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    strings(context, 'invalidTitle'),
                    style: theme.textTheme.titleMedium,
                  ),
                if (years != null) ...[
                  const SizedBox(height: NexSpacing.xs),
                  Text(years, style: theme.textTheme.titleMedium),
                ],
                if (next != null) ...[
                  const SizedBox(height: NexSpacing.sm),
                  Text(
                    strings(context, 'bothCalendars', {
                      'a': occasionDateText(context, next.date, solar: true),
                      'b': occasionDateText(context, next.date, solar: false),
                    }),
                    key: const ValueKey('occasion-both-calendars'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: NexSpacing.xs),
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: NexSpacing.sm),
                    child: Text(
                      strings(context, 'fixDate'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                const SizedBox(height: NexSpacing.sm),
                Text(
                  reminderLine(),
                  key: const ValueKey('occasion-reminder-line'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (occasion.note.trim().isNotEmpty) ...[
            const SizedBox(height: NexSpacing.md),
            NexPanel(
              icon: Icons.notes_outlined,
              child: NexTextSurface(occasion.note, selectable: true),
            ),
          ],
          const SizedBox(height: NexSpacing.md),
          NexPanel(
            title: strings(context, 'greetingTitle'),
            icon: Icons.chat_bubble_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NexTextSurface(
                  occasionGreeting(context, occasion.kind),
                  key: const ValueKey('occasion-greeting'),
                  selectable: true,
                ),
                const SizedBox(height: NexSpacing.sm),
                Wrap(
                  spacing: NexSpacing.sm,
                  children: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('occasion-copy-greeting'),
                      onPressed: () async {
                        await nexModuleCopyText(
                          occasionGreeting(context, occasion.kind),
                        );
                        if (!context.mounted) return;
                        nexShowBanner(
                          context,
                          message: strings(context, 'greetingCopied'),
                        );
                      },
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(strings(context, 'copyGreeting')),
                    ),
                    TextButton.icon(
                      key: const ValueKey('occasion-share-greeting'),
                      onPressed: () => unawaited(
                        nexModuleShareText(
                          occasionGreeting(context, occasion.kind),
                        ),
                      ),
                      icon: const Icon(Icons.ios_share),
                      label: Text(strings(context, 'shareGreeting')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
