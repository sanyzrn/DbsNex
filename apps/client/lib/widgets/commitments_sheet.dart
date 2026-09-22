import 'dart:async';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../l10n/relative_span.dart';
import '../platform/nex_services.dart';
import 'nex_dialog.dart';

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
/// Reached from Settings. Not from the capture button, and not from a tab: it
/// is a list somebody sets up once and then mostly reads about in the brief,
/// so putting it one tap from the timeline would be giving permanent screen
/// furniture to something touched twice a month.
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
    await widget.services.markCommitmentMet(commitment.id);
    await _load();
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final all = _all;
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
          if (all == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: NexSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (all.isEmpty)
            _Empty(l10n: l10n)
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
    final overdue = [for (final c in all) if (c.isOverdue(now)) c];
    final upcoming = [
      for (final c in all)
        if (!c.paused && !c.isOverdue(now)) c,
    ];
    final paused = [for (final c in all) if (c.paused) c];
    int byDate(NexCommitment a, NexCommitment b) => a.dueAt.compareTo(b.dueAt);
    overdue.sort(byDate);
    upcoming.sort(byDate);
    paused.sort(byDate);

    Widget row(NexCommitment c) => _CommitmentRow(
      commitment: c,
      onMet: () => unawaited(_markMet(c)),
      onEdit: () => unawaited(_edit(c)),
      onDelete: () => unawaited(_delete(c)),
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

/// A heading over one run of the list.
///
/// Overdue takes the danger colour and the others do not: it is the only one
/// of the three that is about something having gone wrong.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label, required this.urgent});

  final String label;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.xs),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: urgent
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        textDirection: nexDirectionOf(label),
      ),
    );
  }
}

/// Nothing here yet — said as an invitation rather than as a state.
class _Empty extends StatelessWidget {
  const _Empty({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.lg),
      child: Column(
        children: [
          Icon(
            Icons.event_repeat_outlined,
            size: 32,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: NexSpacing.sm),
          // Two lines in the string: what this is, then three examples. The
          // examples are the part that does the work — "recurring item" is
          // a category nobody thinks in, and "the rent" is not.
          Text(
            l10n.commitmentsEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
            textDirection: nexDirectionOf(l10n.commitmentsEmpty),
          ),
        ],
      ),
    );
  }
}

class _CommitmentRow extends StatelessWidget {
  const _CommitmentRow({
    required this.commitment,
    required this.onMet,
    required this.onEdit,
    required this.onDelete,
  });

  final NexCommitment commitment;
  final VoidCallback onMet;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final overdue = commitment.isOverdue(now);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(NexRadius.md),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(NexRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      commitment.title,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nexCommitmentSubtitle(l10n, commitment, now),
                      style: theme.textTheme.bodySmall?.copyWith(
                        // Overdue is the one state worth colouring. Everything
                        // else on this screen is simply a date.
                        color: overdue
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.commitmentMarkMet,
                onPressed: onMet,
                icon: const Icon(Icons.check_circle_outline),
              ),
              IconButton(
                tooltip: l10n.delete,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "every month · due in 2 days", or "every 2h · 3 of 7 today".
///
/// Top-level rather than a method, so the row and the editor's preview say the
/// same sentence about the same commitment without one of them drifting.
String nexCommitmentSubtitle(
  AppLocalizations l10n,
  NexCommitment commitment,
  DateTime now,
) {
  final cadence = nexCadenceLabel(l10n, commitment.cadence, commitment.every);
  if (commitment.paused) return '$cadence · ${l10n.commitmentPaused}';
  final tally = commitment.timesPerDay;
  if (tally != null) {
    return '$cadence · ${l10n.commitmentTally(commitment.metOn(now), tally)}';
  }
  final away = commitment.dueAt.difference(now);
  final when = away.isNegative
      ? l10n.commitmentOverdue(nexRelativeSpan(l10n, -away))
      : l10n.commitmentDueIn(nexRelativeSpan(l10n, away));
  return '$cadence · $when';
}

String nexCadenceLabel(AppLocalizations l10n, NexCadence cadence, int every) =>
    switch (cadence) {
      NexCadence.hours => l10n.cadenceHours(every),
      NexCadence.days => l10n.cadenceDays(every),
      NexCadence.weeks => l10n.cadenceWeeks(every),
      NexCadence.months => l10n.cadenceMonths(every),
      NexCadence.years => l10n.cadenceYears(every),
    };

/// Setting one up, or changing one.
///
/// Five fields, and the fifth is the one that makes these worth having: how
/// far ahead of the date it is worth being told. It is left on "whatever
/// suits this cadence" unless somebody moves it, so the common case is four
/// fields and the app's judgement — a year's notice needs a week, a month's
/// needs a couple of days, and nobody wants to be asked.
class CommitmentEditor extends StatefulWidget {
  const CommitmentEditor({super.key, required this.services, this.existing});

  final NexServices services;
  final NexCommitment? existing;

  static Future<bool?> show(
    BuildContext context, {
    required NexServices services,
    NexCommitment? existing,
  }) => nexShowSheet<bool>(
    context: context,
    builder: (_) =>
        CommitmentEditor(services: services, existing: existing),
  );

  @override
  State<CommitmentEditor> createState() => _CommitmentEditorState();
}

class _CommitmentEditorState extends State<CommitmentEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late NexCadence _cadence = widget.existing?.cadence ?? NexCadence.months;
  late int _every = widget.existing?.every ?? 1;
  late DateTime _dueAt =
      widget.existing?.dueAt ?? _defaultDue(DateTime.now());
  late Duration? _lead = widget.existing?.lead;
  late bool _notify = widget.existing?.notify ?? true;
  late bool _window =
      widget.existing?.windowStart != null &&
      widget.existing?.windowEnd != null;
  late int _windowStart = widget.existing?.windowStart ?? 8 * 60;
  late int _windowEnd = widget.existing?.windowEnd ?? 23 * 60;
  bool _saving = false;

  /// Tomorrow morning, on the hour.
  ///
  /// Not "now": a commitment created at 14:37 and due at 14:37 is due the
  /// moment it is saved, which makes the first thing the feature ever does an
  /// overdue item.
  static DateTime _defaultDue(DateTime now) =>
      DateTime(now.year, now.month, now.day, 9).add(const Duration(days: 1));

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt),
    );
    if (!mounted) return;
    setState(() {
      _dueAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time?.hour ?? _dueAt.hour,
        time?.minute ?? _dueAt.minute,
      );
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final existing = widget.existing;
    final commitment = existing == null
        ? NexCommitment(
            id: newUuidV7(),
            title: title,
            cadence: _cadence,
            every: _every,
            dueAt: _dueAt,
            lead: _lead,
            windowStart: _window ? _windowStart : null,
            windowEnd: _window ? _windowEnd : null,
            notify: _notify,
            createdAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            title: title,
            cadence: _cadence,
            every: _every,
            dueAt: _dueAt,
            lead: _lead,
            clearLead: _lead == null,
            windowStart: _window ? _windowStart : null,
            windowEnd: _window ? _windowEnd : null,
            clearWindow: !_window,
            notify: _notify,
            updatedAt: now,
          );
    await widget.services.saveCommitment(commitment);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Only the hourly cadence gets a waking window, because it is the only
    // one fine enough to fire while somebody is asleep. Offering it on a
    // yearly renewal would be offering to move a date nobody asked to move.
    final hourly = _cadence == NexCadence.hours;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        MediaQuery.viewInsetsOf(context).bottom + NexSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null
                  ? l10n.commitmentAdd
                  : l10n.commitmentEdit,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: NexSpacing.sm),
            NexAutoDirection(
              controller: _title,
              builder: (context, direction) => TextField(
                controller: _title,
                selectionWidthStyle: BoxWidthStyle.tight,
                contextMenuBuilder: nexReadingMenu,
                textDirection: direction,
                textAlign: TextAlign.start,
                autofocus: widget.existing == null,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.commitmentTitleLabel,
                  hintText: l10n.commitmentTitleHint,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            // Plain `DropdownButton`s in list rows rather than
            // `DropdownButtonFormField`s, to match the lead-time row below
            // and because the form field's `value` is deprecated in favour of
            // `initialValue` on some versions of this SDK and absent on
            // others — a compile risk for no gain on a two-field form.
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.commitmentEvery),
              trailing: DropdownButton<NexCadence>(
                value: _cadence,
                underline: const SizedBox.shrink(),
                items: [
                  for (final cadence in NexCadence.values)
                    DropdownMenuItem(
                      value: cadence,
                      child: Text(nexCadenceLabel(l10n, cadence, _every)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _cadence = value);
                },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.commitmentCount),
              trailing: DropdownButton<int>(
                value: _every,
                underline: const SizedBox.shrink(),
                items: [
                  for (final n in const [1, 2, 3, 4, 6, 8, 12])
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _every = value);
                },
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.commitmentNextDue),
              subtitle: Text(_dateLabel(_dueAt)),
              trailing: const Icon(Icons.event_outlined),
              onTap: () => unawaited(_pickDate()),
            ),
            // The field the whole feature turns on, and the one that is
            // usually left alone.
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.commitmentLead),
              subtitle: Text(
                _lead == null
                    ? l10n.commitmentLeadAuto(
                        nexRelativeSpan(
                          l10n,
                          nexDefaultLead(_cadence, _every),
                        ),
                      )
                    : nexRelativeSpan(l10n, _lead!),
              ),
              trailing: DropdownButton<int>(
                value: _lead?.inHours ?? -1,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: -1, child: Text(l10n.commitmentAuto)),
                  for (final hours in const [0, 6, 24, 48, 24 * 7, 24 * 30])
                    DropdownMenuItem(
                      value: hours,
                      child: Text(
                        hours == 0
                            ? l10n.commitmentLeadNone
                            : nexRelativeSpan(l10n, Duration(hours: hours)),
                      ),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _lead = value == null || value < 0
                      ? null
                      : Duration(hours: value),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.commitmentNotify),
              subtitle: Text(
                _notify ? l10n.commitmentNotifyOn : l10n.commitmentNotifyOff,
              ),
              value: _notify,
              onChanged: (value) => setState(() => _notify = value),
            ),
            if (hourly) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.commitmentWindow),
                subtitle: Text(
                  _window
                      ? '${_clock(_windowStart)} – ${_clock(_windowEnd)}'
                      : l10n.commitmentWindowOff,
                ),
                value: _window,
                onChanged: (value) => setState(() => _window = value),
              ),
              if (_window)
                Row(
                  children: [
                    Expanded(
                      child: _TimeField(
                        label: l10n.commitmentWindowFrom,
                        minutes: _windowStart,
                        onChanged: (value) =>
                            setState(() => _windowStart = value),
                      ),
                    ),
                    const SizedBox(width: NexSpacing.sm),
                    Expanded(
                      child: _TimeField(
                        label: l10n.commitmentWindowTo,
                        minutes: _windowEnd,
                        onChanged: (value) =>
                            setState(() => _windowEnd = value),
                      ),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: NexSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: NexSpacing.sm),
                FilledButton(
                  onPressed: _title.text.trim().isEmpty || _saving
                      ? null
                      : () => unawaited(_save()),
                  child: Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  static String _dateLabel(DateTime when) =>
      '${when.year}-${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')} ${_clock(when.hour * 60 + when.minute)}';
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: Theme.of(context).textTheme.bodySmall),
    subtitle: Text(_CommitmentEditorState._clock(minutes)),
    onTap: () async {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      );
      if (picked != null) onChanged(picked.hour * 60 + picked.minute);
    },
  );
}
