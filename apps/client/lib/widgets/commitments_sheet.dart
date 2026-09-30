import 'feature_label.dart';
import 'recurring_attachments.dart';
import 'recurring_calendar.dart';
import 'recurring_options.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../l10n/relative_span.dart';
import '../platform/nex_services.dart';
import 'nex_dialog.dart';
import 'nex_banner.dart';
import 'draft_guard.dart';
import 'nex_time_picker.dart';

part 'commitments/commitment_editor.dart';
part 'commitments/commitment_rows.dart';

/// The standing obligations: the insurance every year, the rent every month,
/// the tablet every eight hours, the glass of water every two.
///
/// A screen of its own, and that is the point rather than an implementation
/// detail. These deliberately do not appear on the timeline — a tablet three
/// times a day is ninety rows a month in a stream whose whole claim is that
/// it is worth scrolling. They surface where they are actually useful: in the
/// daily brief, each one from its own lead time, and here when somebody wants
/// to see the whole list.
///
/// Reached from Recurring beside Capture in the home dock.
class CommitmentsSheet extends StatefulWidget {
  const CommitmentsSheet({super.key, required this.services});

  final NexServices services;

  static Future<void> show(
    BuildContext context, {
    required NexServices services,
  }) => nexShowSheet<void>(
    context: context,
    builder: (_) => CommitmentsSheet(services: services),
  );

  @override
  State<CommitmentsSheet> createState() => _CommitmentsSheetState();
}

class _CommitmentsSheetState extends State<CommitmentsSheet> {
  List<NexCommitment>? _all;
  String _view = 'all';
  bool _working = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final all = await widget.services.commitments();
    if (mounted) setState(() => _all = all);
  }

  Future<void> _edit([NexCommitment? existing]) async {
    final saved = await CommitmentEditor.show(
      context,
      existing: existing,
      services: widget.services,
    );
    if (saved == true) await _load();
  }

  /// Ticks one off, which rolls it forward rather than finishing it.
  ///
  /// The difference between a commitment and a reminder, in one line: a note's
  /// reminder is spent once it has rung, and this one is due again — the
  /// useful thing the app can do at that moment is work out when.
  Future<void> _markMet(NexCommitment commitment) async {
    await _applyOccurrence(commitment, commitment.met(DateTime.now()));
  }

  Future<void> _delete(NexCommitment commitment) async {
    final l10n = AppLocalizations.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.commitmentDeleteTitle),
        content: NexDialogBody(child: Text(commitment.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (sure != true) return;
    if (!mounted) return;
    await widget.services.deleteCommitment(commitment.id);
    await _load();
  }

  Future<void> _applyOccurrence(
    NexCommitment before,
    NexCommitment next,
  ) async {
    if (_working) return;
    _working = true;
    try {
      final current = (await widget.services.commitments())
          .where((c) => c.id == before.id)
          .firstOrNull;
      if (current == null || current.rev != before.rev) {
        await _load();
        return;
      }
      final saved = await widget.services.saveCommitment(next);
      await _load();
      if (!mounted) return;
      nexShowBanner(
        context,
        message: nexLabel(context, 'Recurring item updated', 'تعهد به‌روز شد'),
        actionLabel: AppLocalizations.of(context).undo,
        onAction: () async {
          final latest = (await widget.services.commitments())
              .where((c) => c.id == before.id)
              .firstOrNull;
          if (latest == null || latest.rev != saved.rev) return;
          await widget.services.saveCommitment(
            NexCommitment(
              id: before.id,
              title: before.title,
              cadence: before.cadence,
              every: before.every,
              dueAt: before.dueAt,
              createdAt: before.createdAt,
              updatedAt: DateTime.now(),
              lead: before.lead,
              windowStart: before.windowStart,
              windowEnd: before.windowEnd,
              lastMetAt: before.lastMetAt,
              metToday: before.metToday,
              metTodayOn: before.metTodayOn,
              paused: before.paused,
              notify: before.notify,
              details: before.details,
              rev: saved.rev + 1,
            ),
          );
          await _load();
        },
      );
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).captureFailed,
        );
      }
    } finally {
      _working = false;
    }
  }

  Future<void> _actions(NexCommitment c) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (id, en, fa, icon) in [
              ('hour', 'In one hour', 'یک ساعت دیگر', Icons.snooze),
              (
                'tomorrow',
                'Tomorrow, same time',
                'فردا همین ساعت',
                Icons.event,
              ),
              ('custom', 'Choose a time', 'زمان دلخواه', Icons.schedule),
              ('skip', 'Skip this occurrence', 'رد این نوبت', Icons.skip_next),
              ('history', 'Completion history', 'سابقهٔ انجام', Icons.history),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(nexLabel(ctx, en, fa)),
                onTap: () => Navigator.pop(ctx, id),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'history') {
      await _history(c);
      return;
    }
    final now = DateTime.now();
    if (choice == 'skip') {
      await _applyOccurrence(
        c,
        c.copyWith(
          dueAt: nexAdvance(c, after: now),
          details: c.recordOccurrence('skip', now),
          updatedAt: now,
        ),
      );
      return;
    }
    DateTime? date;
    if (choice == 'hour') date = now.add(const Duration(hours: 1));
    if (choice == 'tomorrow') {
      date = DateTime(
        now.year,
        now.month,
        now.day + 1,
        c.dueAt.hour,
        c.dueAt.minute,
      );
    }
    if (choice == 'custom') {
      final d = await nexPickDate(
        context,
        solar: widget.services.solarCalendar,
        initial: now,
        first: now,
        last: DateTime(2100),
      );
      if (!mounted || d == null) return;
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now),
      );
      if (!mounted || t == null) return;
      date = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    }
    if (date == null || !date.isAfter(now)) return;
    await _applyOccurrence(
      c,
      c.copyWith(
        dueAt: date,
        details: {
          ...c.details,
          'scheduledDue': c.scheduledDue.toIso8601String(),
        },
        updatedAt: now,
      ),
    );
  }

  Future<void> _history(NexCommitment c) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .65,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                nexLabel(
                  ctx,
                  'Completion history · latest 500',
                  'سابقهٔ انجام · ۵۰۰ نوبت آخر',
                ),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              if (c.history.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    nexLabel(ctx, 'No history yet', 'هنوز سابقه‌ای نیست'),
                  ),
                ),
              for (final item in c.history.reversed)
                ListTile(
                  leading: Icon(
                    item['action'] == 'done'
                        ? Icons.check_circle_outline
                        : Icons.skip_next,
                  ),
                  title: Text(
                    nexDisplayDate(
                      DateTime.parse(item['at'] as String),
                      solar: widget.services.solarCalendar,
                      persian: Localizations.localeOf(ctx).languageCode == 'fa',
                      time: true,
                    ),
                  ),
                  subtitle: Text(item['note'] as String? ?? ''),
                  trailing: const Icon(Icons.edit_note),
                  onTap: () async {
                    final controller = TextEditingController(
                      text: item['note'] as String? ?? '',
                    );
                    final note = await showDialog<String>(
                      context: ctx,
                      builder: (dialog) => AlertDialog(
                        title: Text(
                          nexLabel(
                            dialog,
                            'Occurrence note',
                            'یادداشت این نوبت',
                          ),
                        ),
                        content: TextField(
                          controller: controller,
                          maxLength: 300,
                          maxLines: 3,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog),
                            child: Text(AppLocalizations.of(dialog).cancel),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialog, controller.text.trim()),
                            child: Text(AppLocalizations.of(dialog).save),
                          ),
                        ],
                      ),
                    );
                    // Controller is kept until the dialog's exit animation has finished.
                    Future<void>.delayed(
                      const Duration(milliseconds: 350),
                      controller.dispose,
                    );
                    if (note == null || !mounted) return;
                    final latest = (await widget.services.commitments())
                        .where((v) => v.id == c.id)
                        .firstOrNull;
                    if (latest == null) return;
                    await widget.services.saveCommitment(
                      latest.copyWith(
                        details: {
                          ...latest.details,
                          'history': [
                            for (final h in latest.history)
                              if (h['at'] == item['at'] &&
                                  h['due'] == item['due'])
                                {...h, 'note': note}
                              else
                                h,
                          ],
                        },
                        updatedAt: DateTime.now(),
                      ),
                    );
                    await _load();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _costSummary(List<NexCommitment> all, DateTime now) {
    final end = DateTime(now.year, now.month, now.day + 30);
    final totals = <String, int>{};
    for (final c in all.where((c) => !c.paused && c.amountMinor != null)) {
      var due = c.dueAt.isBefore(now)
          ? nexAdvance(c, after: now.subtract(const Duration(microseconds: 1)))
          : c.dueAt;
      for (var count = 0; due.isBefore(end) && count < 1000; count++) {
        if (!due.isBefore(now)) {
          totals[c.currency] = (totals[c.currency] ?? 0) + c.amountMinor!;
        }
        due = nexAdvance(
          c.copyWith(dueAt: due, details: {...c.details, 'scheduledDue': null}),
          after: due,
        );
      }
    }
    return totals.isEmpty
        ? const SizedBox.shrink()
        : Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nexLabel(
                      context,
                      'Payments in the next 30 days',
                      'پرداخت‌های ۳۰ روز آینده',
                    ),
                  ),
                  for (final e in totals.entries)
                    Text(
                      nexDigits(
                        '${(e.value / 100).toStringAsFixed(2)} ${e.key}',
                        persian:
                            Localizations.localeOf(context).languageCode ==
                            'fa',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                ],
              ),
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final source = _all;
    final today = DateUtils.dateOnly(DateTime.now());
    final all = source
        ?.where(
          (c) => switch (_view) {
            'today' => !c.paused && DateUtils.isSameDay(c.dueAt, today),
            'overdue' => c.isOverdue(DateTime.now()),
            'week' =>
              !c.paused &&
                  !c.dueAt.isBefore(today) &&
                  c.dueAt.isBefore(today.add(const Duration(days: 7))),
            // The calendar draws every item on its own days.
            'calendar' => true,
            _ => true,
          },
        )
        .toList();
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        NexSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.commitmentsTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    // How many there are, under the title. A count is the
                    // one thing somebody opening a list already wants to
                    // know and would otherwise have to work out by looking.
                    if (all != null && all.isNotEmpty)
                      Text(
                        l10n.commitmentsCount(all.length),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.commitmentAdd,
                onPressed: () => unawaited(_edit()),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          // What a recurring item actually is, and what the app does with
          // one. This page had a title, a plus and a list, and nothing at
          // all that said why anybody would put something in it — which is
          // the whole of what was wrong with it.
          const SizedBox(height: NexSpacing.xs),
          Text(
            l10n.commitmentsAbout,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
            textDirection: nexDirectionOf(l10n.commitmentsAbout),
          ),
          const SizedBox(height: NexSpacing.md),
          Wrap(
            spacing: 6,
            children: [
              for (final (id, en, fa) in [
                ('all', 'All', 'همه'),
                ('today', 'Today', 'امروز'),
                ('overdue', 'Overdue', 'عقب‌افتاده'),
                ('week', 'Next 7 days', '۷ روز آینده'),
                ('calendar', 'Calendar', 'تقویم'),
              ])
                ChoiceChip(
                  label: Text(nexLabel(context, en, fa)),
                  selected: _view == id,
                  onSelected: (_) => setState(() => _view = id),
                ),
            ],
          ),
          if (source != null) _costSummary(source, now),
          const SizedBox(height: 8),
          if (all == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: NexSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (all.isEmpty)
            // Scrollable, like the list it stands in for: at the largest text
            // sizes the explanation is taller than what is left of the sheet.
            Flexible(
              child: SingleChildScrollView(child: _Empty(l10n: l10n)),
            )
          else if (_view == 'calendar')
            Flexible(
              child: SingleChildScrollView(
                child: RecurringCalendar(
                  commitments: all,
                  solar: widget.services.solarCalendar,
                  onActions: (c) => unawaited(_actions(c)),
                ),
              ),
            )
          else
            Flexible(child: _grouped(l10n, theme, all, now)),
        ],
      ),
    );
  }

  /// The list, in the order somebody actually needs it.
  ///
  /// Flat and sorted by date, the thing that has been overdue for a week sat
  /// wherever the arithmetic put it, between two items that are fine. Three
  /// groups say the only thing this list is for: what has slipped, what is
  /// coming, and what is not running at all.
  Widget _grouped(
    AppLocalizations l10n,
    ThemeData theme,
    List<NexCommitment> all,
    DateTime now,
  ) {
    final overdue = [
      for (final c in all)
        if (c.isOverdue(now)) c,
    ];
    final upcoming = [
      for (final c in all)
        if (!c.paused && !c.isOverdue(now)) c,
    ];
    final paused = [
      for (final c in all)
        if (c.paused) c,
    ];
    int byDate(NexCommitment a, NexCommitment b) => a.dueAt.compareTo(b.dueAt);
    overdue.sort(byDate);
    upcoming.sort(byDate);
    paused.sort(byDate);

    Widget row(NexCommitment c) => _CommitmentRow(
      commitment: c,
      onMet: () => unawaited(_markMet(c)),
      onEdit: () => unawaited(_edit(c)),
      onDelete: () => unawaited(_delete(c)),
      onActions: () => unawaited(_actions(c)),
    );

    return ListView(
      shrinkWrap: true,
      children: [
        for (final (label, group, urgent) in [
          (l10n.commitmentsOverdue, overdue, true),
          (l10n.commitmentsComingUp, upcoming, false),
          (l10n.commitmentsRested, paused, false),
        ])
          if (group.isNotEmpty) ...[
            _GroupLabel(label: label, urgent: urgent),
            for (final c in group) ...[
              row(c),
              const SizedBox(height: NexSpacing.xs),
            ],
            const SizedBox(height: NexSpacing.sm),
          ],
      ],
    );
  }
}
