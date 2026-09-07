import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'due_label.dart';

/// When a reminder should fire, chosen on one screen.
///
/// It used to be a list: four shortcut rows, then "Pick a time…", which opened
/// the Material date dialog, and then the Material clock dialog. Anything the
/// four shortcuts did not anticipate — the overwhelmingly common case of a
/// specific hour on a specific day — cost two modal dialogs on top of the
/// sheet, and backing out of the second one silently threw the first away.
///
/// This is the shape a messaging app's "remind me" uses, and it is better for
/// the reason those apps landed on it: the whole answer is three columns and
/// the button spells out what it is about to do. No dialog opens on top of
/// another, there is one place to confirm, and the shortcuts are still one tap
/// — they move the wheels instead of closing the sheet, so "tomorrow morning,
/// but at eight" is a tap and one flick rather than a different flow.
class ReminderWheel extends StatefulWidget {
  const ReminderWheel({
    super.key,
    required this.note,
    required this.now,
    required this.onSubmit,
    required this.onClear,
  });

  final Note note;

  /// Passed in rather than read here so the sheet's idea of "today" cannot
  /// drift from the caller's between building the shortcuts and reading them.
  final DateTime now;

  final void Function(DateTime when, NoteRepeat repeat) onSubmit;
  final VoidCallback onClear;

  /// How far ahead the day wheel goes. A year of rows costs nothing — the
  /// wheel builds lazily — and a reminder further out than that is a calendar
  /// entry, not a note.
  static const days = 366;

  /// Named so a test can drive one column instead of guessing which
  /// [ListWheelScrollView] in tree order is the hour.
  static const dayKey = ValueKey('reminder-day');
  static const hourKey = ValueKey('reminder-hour');
  static const minuteKey = ValueKey('reminder-minute');

  @override
  State<ReminderWheel> createState() => _ReminderWheelState();
}

class _ReminderWheelState extends State<ReminderWheel> {
  static const _itemExtent = 44.0;

  late final FixedExtentScrollController _dayController;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  late DateTime _midnight;
  late int _day;
  late int _hour;
  late int _minute;
  late NoteRepeat _repeat = widget.note.dueRepeat;

  @override
  void initState() {
    super.initState();
    final now = widget.now;
    _midnight = DateTime(now.year, now.month, now.day);
    // Opens on the reminder already set — editing should start from what is
    // there, not from a default that throws it away. Unless it has already
    // gone off: an overdue reminder would open this sheet with its own button
    // dead, and "in an hour" is what someone reaching for an overdue reminder
    // almost always wants next.
    final existing = widget.note.dueAt?.toLocal();
    final start = existing != null && existing.isAfter(now)
        ? existing
        : now.add(const Duration(hours: 1));
    _day = DateTime(
      start.year,
      start.month,
      start.day,
    ).difference(_midnight).inDays.clamp(0, ReminderWheel.days - 1);
    _hour = start.hour;
    _minute = start.minute;
    _dayController = FixedExtentScrollController(initialItem: _day);
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _dayController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  DateTime get _chosen =>
      _midnight.add(Duration(days: _day, hours: _hour, minutes: _minute));

  bool get _isPast => !_chosen.isAfter(widget.now);

  /// Drives the wheels from a shortcut, so the shortcut and the wheels are
  /// never showing different answers.
  void _goTo(DateTime when) {
    final day = DateTime(
      when.year,
      when.month,
      when.day,
    ).difference(_midnight).inDays;
    _dayController.animateToItem(
      day,
      duration: NexMotion.standard,
      curve: NexMotion.curve,
    );
    _hourController.animateToItem(
      when.hour,
      duration: NexMotion.standard,
      curve: NexMotion.curve,
    );
    _minuteController.animateToItem(
      when.minute,
      duration: NexMotion.standard,
      curve: NexMotion.curve,
    );
  }

  String _dayLabel(BuildContext context, int index) {
    final l10n = AppLocalizations.of(context);
    if (index == 0) return l10n.remindDayToday;
    if (index == 1) return l10n.remindDayTomorrow;
    return MaterialLocalizations.of(
      context,
    ).formatMediumDate(_midnight.add(Duration(days: index)));
  }

  String _action(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final time = material.formatTimeOfDay(
      TimeOfDay(hour: _hour, minute: _minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return switch (_day) {
      0 => l10n.remindActionToday(time),
      1 => l10n.remindActionTomorrow(time),
      _ => l10n.remindActionOn(material.formatMediumDate(_chosen), time),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final material = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final now = widget.now;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.lg,
            NexSpacing.sm,
            NexSpacing.lg,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(l10n.remindTitle, style: theme.textTheme.titleLarge),
              ),
              Icon(
                Icons.notifications_none,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        // What is already set, before anything that would replace it. Without
        // it the sheet asks someone to change a reminder they cannot read.
        if (widget.note.dueAt case final due?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.lg,
              NexSpacing.xs,
              NexSpacing.lg,
              0,
            ),
            child: Text(
              l10n.remindCurrent(
                widget.note.dueRepeat == NoteRepeat.once
                    ? nexDueExact(context, due)
                    : l10n.remindRepeatingAt(
                        nexDueExact(context, due),
                        nexRepeatLabel(l10n, widget.note.dueRepeat),
                      ),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        const SizedBox(height: NexSpacing.sm),
        // The shortcuts, kept from the list this replaced. They set the wheels
        // rather than closing the sheet: "tomorrow morning, but at eight" is
        // then a tap and one flick instead of a different route through the
        // interface.
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
            children: [
              for (final (label, at) in _shortcuts(l10n, now))
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: NexSpacing.sm),
                  child: ActionChip(
                    label: Text(label),
                    onPressed: () => _goTo(at),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        _WheelRow(
          itemExtent: _itemExtent,
          children: [
            _Wheel(
              key: ReminderWheel.dayKey,
              flex: 5,
              controller: _dayController,
              itemExtent: _itemExtent,
              count: ReminderWheel.days,
              onChanged: (index) => setState(() => _day = index),
              builder: (context, index) => _dayLabel(context, index),
            ),
            _Wheel(
              key: ReminderWheel.hourKey,
              flex: 2,
              controller: _hourController,
              itemExtent: _itemExtent,
              count: 24,
              looping: true,
              onChanged: (index) => setState(() => _hour = index % 24),
              builder: (context, index) => material.formatHour(
                TimeOfDay(hour: index, minute: 0),
                alwaysUse24HourFormat: use24,
              ),
            ),
            _Wheel(
              key: ReminderWheel.minuteKey,
              flex: 2,
              controller: _minuteController,
              itemExtent: _itemExtent,
              count: 60,
              looping: true,
              onChanged: (index) => setState(() => _minute = index % 60),
              builder: (context, index) =>
                  material.formatMinute(TimeOfDay(hour: 0, minute: index)),
            ),
          ],
        ),
        const SizedBox(height: NexSpacing.sm),
        Center(
          child: _RepeatChip(
            repeat: _repeat,
            onChanged: (value) => setState(() => _repeat = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.lg,
            NexSpacing.md,
            NexSpacing.lg,
            NexSpacing.sm,
          ),
          child: FilledButton(
            // A reminder in the past is a reminder that never arrives: the
            // scheduler drops a past-due one-off on purpose, so a button that
            // stayed live here would report "Reminder set" for an alarm that
            // does not exist.
            onPressed: _isPast
                ? null
                : () => widget.onSubmit(_chosen, _repeat),
            child: Text(_isPast ? l10n.remindPast : _action(context)),
          ),
        ),
        if (widget.note.dueAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.sm),
            child: TextButton.icon(
              onPressed: widget.onClear,
              icon: const Icon(Icons.notifications_off_outlined, size: 18),
              label: Text(l10n.remindClear),
            ),
          ),
      ],
    );
  }

  List<(String, DateTime)> _shortcuts(AppLocalizations l10n, DateTime now) {
    final evening = DateTime(now.year, now.month, now.day, 20);
    return [
      (l10n.remindLater, now.add(const Duration(hours: 1))),
      (
        l10n.remindEvening,
        // Past eight already: "this evening" can only mean tomorrow's.
        evening.isAfter(now) ? evening : evening.add(const Duration(days: 1)),
      ),
      (l10n.remindTomorrow, DateTime(now.year, now.month, now.day + 1, 9)),
      (l10n.remindNextWeek, DateTime(now.year, now.month, now.day + 7, 9)),
    ];
  }
}

/// The three columns, with the selection band drawn behind them.
///
/// Behind, not between: the band is one shape across the whole row, so the
/// columns read as one control rather than three lists that happen to be
/// adjacent.
class _WheelRow extends StatelessWidget {
  const _WheelRow({required this.children, required this.itemExtent});

  final List<Widget> children;
  final double itemExtent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: itemExtent * 5,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: itemExtent,
            margin: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(NexRadius.md),
            ),
          ),
          Row(children: children),
        ],
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    super.key,
    required this.flex,
    required this.controller,
    required this.itemExtent,
    required this.count,
    required this.onChanged,
    required this.builder,
    this.looping = false,
  });

  final int flex;
  final FixedExtentScrollController controller;
  final double itemExtent;
  final int count;
  final ValueChanged<int> onChanged;
  final String Function(BuildContext context, int index) builder;

  /// Hours and minutes wrap; days do not. Scrolling past 23:59 back to 00:00
  /// is how every clock behaves, and stopping dead at the end of a list of
  /// sixty numbers is not.
  final bool looping;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(BuildContext context, int index) => Center(
      child: Text(
        builder(context, index),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium,
      ),
    );
    return Expanded(
      flex: flex,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: itemExtent,
        physics: const FixedExtentScrollPhysics(),
        // Flat, not a barrel. The default perspective bends a column of dates
        // enough that the row above the selection is noticeably harder to
        // read than the one below it.
        perspective: 0.002,
        diameterRatio: 2.2,
        overAndUnderCenterOpacity: 0.45,
        onSelectedItemChanged: onChanged,
        childDelegate: looping
            ? ListWheelChildLoopingListDelegate(
                children: [
                  for (var i = 0; i < count; i++) Builder(builder: (c) => row(c, i)),
                ],
              )
            : ListWheelChildBuilderDelegate(
                builder: (context, index) =>
                    index < 0 || index >= count ? null : row(context, index),
                childCount: count,
              ),
      ),
    );
  }
}

/// "Repeat: Once", and a menu to change it.
///
/// A chip rather than the segmented row this replaced: repeating is the rare
/// answer, and three permanent buttons spent a whole line of the sheet saying
/// so.
class _RepeatChip extends StatelessWidget {
  const _RepeatChip({required this.repeat, required this.onChanged});

  final NoteRepeat repeat;
  final ValueChanged<NoteRepeat> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<NoteRepeat>(
      initialValue: repeat,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final value in NoteRepeat.values)
          PopupMenuItem(value: value, child: Text(nexRepeatLabel(l10n, value))),
      ],
      child: Chip(
        label: Text('${l10n.remindRepeat}: ${nexRepeatLabel(l10n, repeat)}'),
        avatar: const Icon(Icons.repeat, size: 16),
      ),
    );
  }
}
