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
import 'nex_text_field.dart';
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
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key, required this.services});

  final NexServices services;

  /// A page of its own. It used to be a sheet over the timeline, and a
  /// sheet is the size of a question — which is how it was treated: things
  /// that come round every month, with money and medicine among them, in
  /// something that looked like it could be flicked away.
  static Future<void> show(
    BuildContext context, {
    required NexServices services,
  }) => Navigator.of(context).push<void>(
    NexPageRoute<void>(builder: (_) => RecurringScreen(services: services)),
  );

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
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
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                AppLocalizations.of(ctx).delete,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
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
    if (choice == 'delete') {
      await _delete(c);
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
                        content: NexTextField(
                          controller: controller,
                          maxLength: 300,
                          minLines: 1,
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

  /// What the paying ones add up to over the next thirty days, per
  /// currency.
  Map<String, int> _paymentsAhead(List<NexCommitment> all, DateTime now) {
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
    return totals;
  }

  bool _inView(NexCommitment c, String view, DateTime now) {
    final today = DateUtils.dateOnly(now);
    return switch (view) {
      'today' => !c.paused && DateUtils.isSameDay(c.dueAt, today),
      'overdue' => c.isOverdue(now),
      'week' =>
        !c.paused &&
            !c.dueAt.isBefore(today) &&
            c.dueAt.isBefore(today.add(const Duration(days: 7))),
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final source = _all;
    final now = DateTime.now();
    final calendar = _view == 'calendar';
    final shown = source
        ?.where((c) => calendar || _inView(c, _view, now))
        .toList();
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    return Scaffold(
      floatingActionButton: source == null || source.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => unawaited(_edit()),
              icon: const Icon(Icons.add),
              label: Text(l10n.commitmentAdd),
            ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: Text(l10n.commitmentsTitle)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
            sliver: SliverList.list(
              children: [
                // What a recurring item actually is, and what the app does
                // with one. This page had a title, a plus and a list, and
                // nothing at all that said why anybody would put something
                // in it — which is the whole of what was wrong with it.
                Text(
                  l10n.commitmentsAbout,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                  textDirection: nexDirectionOf(l10n.commitmentsAbout),
                ),
                if (source != null && source.isNotEmpty) ...[
                  const SizedBox(height: NexSpacing.md),
                  // How many there are. A count is the one thing somebody
                  // opening a list already wants to know.
                  Text(
                    l10n.commitmentsCount(source.length),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  _Summary(
                    view: _view,
                    counts: {
                      for (final view in const ['overdue', 'today', 'week'])
                        view: source.where((c) => _inView(c, view, now)).length,
                    },
                    persian: persian,
                    onView: (view) =>
                        setState(() => _view = _view == view ? 'all' : view),
                  ),
                  if (_paymentsAhead(source, now) case final totals
                      when totals.isNotEmpty) ...[
                    const SizedBox(height: NexSpacing.sm),
                    _Payments(totals: totals, persian: persian),
                  ],
                  const SizedBox(height: NexSpacing.md),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.view_agenda_outlined),
                        label: Text(nexLabel(context, 'List', 'فهرست')),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(nexLabel(context, 'Calendar', 'تقویم')),
                      ),
                    ],
                    selected: {calendar},
                    onSelectionChanged: (value) => setState(
                      () => _view = value.first ? 'calendar' : 'all',
                    ),
                  ),
                  if (!calendar) ...[
                    const SizedBox(height: NexSpacing.sm),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final (id, en, fa) in [
                          ('all', 'All', 'همه'),
                          ('today', 'Today', 'امروز'),
                          ('overdue', 'Overdue', 'عقب‌افتاده'),
                          ('week', 'Next 7 days', '۷ روز آینده'),
                        ])
                          ChoiceChip(
                            label: Text(nexLabel(context, en, fa)),
                            selected: _view == id,
                            onSelected: (_) => setState(() => _view = id),
                          ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: NexSpacing.md),
                if (shown == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: NexSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (source!.isEmpty)
                  _Empty(l10n: l10n, onAdd: () => unawaited(_edit()))
                else if (calendar)
                  RecurringCalendar(
                    commitments: shown,
                    solar: widget.services.solarCalendar,
                    onActions: (c) => unawaited(_actions(c)),
                  )
                else if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: NexSpacing.xl,
                    ),
                    child: Text(
                      nexLabel(
                        context,
                        'Nothing in this view.',
                        'در این نما چیزی نیست.',
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ..._grouped(l10n, shown, now),
                // Room for the button floating over the end of the list.
                SizedBox(height: 96 + nexBottomInset(context)),
              ],
            ),
          ),
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
  List<Widget> _grouped(
    AppLocalizations l10n,
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
      onActions: () => unawaited(_actions(c)),
    );

    return [
      for (final (label, group, urgent) in [
        (l10n.commitmentsOverdue, overdue, true),
        (l10n.commitmentsComingUp, upcoming, false),
        (l10n.commitmentsRested, paused, false),
      ])
        if (group.isNotEmpty) ...[
          _GroupLabel(label: label, urgent: urgent, count: group.length),
          for (final c in group) ...[
            row(c),
            const SizedBox(height: NexSpacing.sm),
          ],
          const SizedBox(height: NexSpacing.md),
        ],
    ];
  }
}
