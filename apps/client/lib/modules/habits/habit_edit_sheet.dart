import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'adaptive_segments.dart';
import 'draft_guard.dart';
import 'form_draft.dart';
import 'habit_model.dart';
import 'habit_reminder.dart';
import 'habit_templates.dart';
import 'habit_visuals.dart';
import 'module.dart';
import 'store_state.dart';

/// Creates a habit, or edits one without touching its history (2.4.0): its
/// name and look, how often, and what counts as done. The sheet writes the
/// same record, and every check-in keeps pointing at it. A schedule change
/// reads the past under the new plan; a day already kept stays kept.
Future<void> showHabitEditSheet(
  BuildContext context,
  NexModuleStore store, {
  Habit? habit,
  int firstDay = DateTime.saturday,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (context) =>
      _HabitEditSheet(store: store, habit: habit, firstDay: firstDay),
);

class _HabitEditSheet extends StatefulWidget {
  const _HabitEditSheet({
    required this.store,
    required this.habit,
    required this.firstDay,
  });

  final NexModuleStore store;
  final Habit? habit;
  final int firstDay;

  @override
  State<_HabitEditSheet> createState() => _HabitEditSheetState();
}

class _HabitEditSheetState extends State<_HabitEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late final TextEditingController _unit;
  late HabitPlan _plan;
  late int _target;
  late Set<int> _days;
  late int _every;
  late bool _counted;
  late int _goal;
  late String _icon;
  late int _hue;
  bool _saving = false;
  late final FormDraft _draft;
  bool _restoring = true;
  late final String _recordId = widget.habit?.id ?? widget.store.newId();
  String? _nameError;
  String? _daysError;

  bool get _editing => widget.habit != null;

  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    _name = TextEditingController(text: habit?.name ?? '');
    _note = TextEditingController(text: habit?.note ?? '');
    _unit = TextEditingController(text: habit?.unit ?? '');
    _plan = habit?.plan ?? HabitPlan.daily;
    _target = habit?.weekly == true ? habit!.target : 3;
    _days = {...?habit?.days};
    _every = habit?.every ?? 2;
    _counted = habit?.counted ?? false;
    _goal = habit?.counted == true ? habit!.goal : 8;
    _icon = habit?.icon.isNotEmpty == true ? habit!.icon : 'spark';
    _hue = habit?.hue ?? 0;
    _draft = FormDraft(
      widget.store,
      'habit:${widget.habit?.id ?? 'new'}',
      widget.habit?.toJson() ?? const {},
      {'name': _name, 'note': _note, 'unit': _unit},
      () => {
        'recordId': _recordId,
        'plan': _plan.name,
        'weekly': _plan == HabitPlan.weekly,
        'target': _target,
        'days': (_days.toList()..sort()),
        'every': _every,
        'counted': _counted,
        'goal': _goal,
        'icon': _icon,
        'hue': _hue,
      },
    );
    unawaited(_restoreDraft());
  }

  Future<void> _restoreDraft() async {
    final body = await _draft.load();
    if (!mounted) return;
    if (body != null) {
      _draft.apply(body);
      final plan = HabitPlan.values.where((p) => p.name == body['plan']);
      _plan = plan.isNotEmpty
          ? plan.first
          : body['weekly'] == true
          ? HabitPlan.weekly
          : HabitPlan.daily;
      final target = body['target'];
      if (target is int) _target = target.clamp(1, 7);
      final days = body['days'];
      if (days is List) {
        _days = {
          for (final d in days)
            if (d is int && d >= 1 && d <= 7) d,
        };
      }
      final every = body['every'];
      if (every is int) _every = every.clamp(2, 30);
      if (body['counted'] is bool) _counted = body['counted'] as bool;
      final goal = body['goal'];
      if (goal is int) _goal = goal.clamp(2, 9999);
      final icon = body['icon'];
      if (icon is String && habitIcons.containsKey(icon)) _icon = icon;
      final hue = body['hue'];
      if (hue is int) _hue = hue.clamp(0, habitHues.length - 1);
    }
    _draft.start();
    setState(() => _restoring = false);
  }

  @override
  void dispose() {
    _draft.close();
    _name.dispose();
    _note.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _useTemplate(HabitTemplate template) {
    final strings = habitsStrings;
    setState(() {
      _name.text = strings(context, 'tpl_${template.id}');
      _icon = template.icon;
      _hue = template.hue;
      _plan = template.plan;
      _target = template.target;
      _every = template.every;
      _days = {...template.days};
      _counted = template.counted;
      if (template.counted) {
        _goal = template.goal;
        _unit.text = strings(context, 'tplUnit_${template.id}');
      } else {
        _unit.clear();
      }
      _nameError = null;
      _daysError = null;
    });
  }

  Future<void> _save() async {
    final strings = habitsStrings;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = strings(context, 'nameRequired'));
      return;
    }
    if (_plan == HabitPlan.days && _days.isEmpty) {
      setState(() => _daysError = strings(context, 'daysRequired'));
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final old = widget.habit;
    final habit = Habit(
      id: _recordId,
      name: name,
      note: _note.text.trim(),
      weekly: _plan == HabitPlan.weekly,
      target: _plan == HabitPlan.weekly ? _target : 1,
      // An edit keeps the habit's life story: still archived or not, still
      // born when it was born.
      archived: old?.archived ?? false,
      createdAt: old?.createdAt ?? DateTime.now(),
      plan: _plan,
      days: _days,
      every: _every,
      goal: _counted ? _goal : 1,
      unit: _counted ? _unit.text.trim() : '',
      icon: _icon,
      hue: _hue,
    );
    final saved = await storeWrite(context, () async {
      await widget.store.put('habit', habit.id, habit.toJson());
    });
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    try {
      await _draft.clear();
    } catch (_) {
      /* Saved record remains authoritative. */
    }
    try {
      // A new plan means new days to ring on.
      if (old != null) await habitArmReminder(widget.store, l10n, habit);
    } catch (_) {
      /* Catches up on the next start. */
    }
    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_restoring) _draft.changed();
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final persian = NexModuleStrings.persian(context);
    final hue = habitHues[_hue];
    final color = theme.brightness == Brightness.dark
        ? Color.lerp(hue.base, Colors.white, 0.12)!
        : hue.base;
    Widget section(String key) => Padding(
      padding: const EdgeInsets.only(top: NexSpacing.lg, bottom: NexSpacing.sm),
      child: Text(
        strings(context, key),
        style: theme.textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    Widget stepper({
      required String id,
      required int value,
      required int min,
      required int max,
      required int step,
      required ValueChanged<int> onChanged,
      required String label,
    }) => Row(
      children: [
        IconButton.filledTonal(
          key: ValueKey('$id-minus'),
          tooltip: strings(context, 'less'),
          onPressed: value <= min
              ? null
              : () => onChanged((value - step).clamp(min, max)),
          icon: const Icon(Icons.remove_rounded),
        ),
        Expanded(
          child: Text(
            label,
            key: ValueKey(id),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton.filledTonal(
          key: ValueKey('$id-plus'),
          tooltip: strings(context, 'more1'),
          onPressed: value >= max
              ? null
              : () => onChanged((value + step).clamp(min, max)),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );

    return DraftGuard(
      draft: _draft,
      busy: () => _saving,
      child: AbsorbPointer(
        absorbing: _restoring || _saving,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: NexSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: NexSpacing.md),
                Text(
                  strings(context, _editing ? 'editHabit' : 'newHabit'),
                  style: theme.textTheme.titleLarge,
                ),
                if (!_editing) ...[
                  section('ideas'),
                  SizedBox(
                    height:
                        40 +
                        (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
                          0,
                          60,
                        ),
                    child: ListView(
                      key: const ValueKey('habit-templates'),
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final template in habitTemplates)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: NexSpacing.sm,
                            ),
                            child: ActionChip(
                              key: ValueKey('habit-template-${template.id}'),
                              avatar: Icon(
                                habitIcons[template.icon],
                                size: 18,
                                color: habitHues[template.hue].base,
                              ),
                              label: Text(
                                strings(context, 'tpl_${template.id}'),
                              ),
                              onPressed: () => _useTemplate(template),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: NexSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: AnimatedContainer(
                        duration: NexMotion.of(context, NexMotion.standard),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.16),
                        ),
                        child: Icon(habitIcons[_icon], color: color),
                      ),
                    ),
                    const SizedBox(width: NexSpacing.md),
                    Expanded(
                      // A person's own words, one line: the direction
                      // follows the script they type, as everywhere in Nex.
                      child: NexAutoDirection(
                        controller: _name,
                        builder: (context, _) => TextField(
                          key: const ValueKey('habit-field-name'),
                          controller: _name,
                          autofocus: !_editing,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) {
                            if (_nameError != null) {
                              setState(() => _nameError = null);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: strings(context, 'nameLabel'),
                            hintText: strings(context, 'nameHint'),
                            errorText: _nameError,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                section('look'),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    for (final (i, option) in habitHues.indexed)
                      Semantics(
                        button: true,
                        selected: _hue == i,
                        label: strings(context, 'colour${i + 1}'),
                        excludeSemantics: true,
                        child: InkResponse(
                          key: ValueKey('habit-hue-$i'),
                          onTap: () => setState(() => _hue = i),
                          radius: 24,
                          child: AnimatedContainer(
                            duration: NexMotion.of(context, NexMotion.standard),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: option.base,
                              border: Border.all(
                                color: _hue == i
                                    ? scheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: _hue == i
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: NexSpacing.md),
                Wrap(
                  spacing: NexSpacing.xs,
                  runSpacing: NexSpacing.xs,
                  children: [
                    for (final entry in habitIcons.entries)
                      Semantics(
                        button: true,
                        selected: _icon == entry.key,
                        label: strings(context, 'icon_${entry.key}'),
                        excludeSemantics: true,
                        child: InkResponse(
                          key: ValueKey('habit-icon-${entry.key}'),
                          onTap: () => setState(() => _icon = entry.key),
                          radius: 24,
                          child: AnimatedContainer(
                            duration: NexMotion.of(context, NexMotion.standard),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _icon == entry.key
                                  ? color
                                  : scheme.surfaceContainerHighest,
                            ),
                            child: Icon(
                              entry.value,
                              size: 22,
                              color: _icon == entry.key
                                  ? Colors.white
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                section('howOften'),
                Wrap(
                  key: const ValueKey('habit-field-schedule'),
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    for (final plan in HabitPlan.values)
                      ChoiceChip(
                        key: ValueKey('habit-plan-${plan.name}'),
                        label: Text(strings(context, 'plan_${plan.name}')),
                        selected: _plan == plan,
                        onSelected: (_) => setState(() {
                          _plan = plan;
                          _daysError = null;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: NexSpacing.md),
                switch (_plan) {
                  HabitPlan.daily => Text(
                    strings(context, 'planDailyHint'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  HabitPlan.weekly => Wrap(
                    spacing: NexSpacing.sm,
                    runSpacing: NexSpacing.sm,
                    children: [
                      for (var n = 1; n <= 7; n++)
                        ChoiceChip(
                          key: ValueKey('habit-target-$n'),
                          // "1 times a week" is no-one's English; the
                          // singular chip says it properly.
                          label: Text(
                            strings(
                              context,
                              n == 1 ? 'oneTarget' : 'targetLabel',
                              {'n': n},
                            ),
                          ),
                          selected: _target == n,
                          onSelected: (selected) {
                            if (selected) setState(() => _target = n);
                          },
                        ),
                    ],
                  ),
                  HabitPlan.days => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: NexSpacing.xs,
                        runSpacing: NexSpacing.xs,
                        children: [
                          for (var i = 0; i < 7; i++)
                            Builder(
                              builder: (context) {
                                final day = (widget.firstDay - 1 + i) % 7 + 1;
                                return FilterChip(
                                  key: ValueKey('habit-day-pick-$day'),
                                  label: Text(strings(context, 'wdShort$day')),
                                  showCheckmark: false,
                                  selected: _days.contains(day),
                                  onSelected: (on) => setState(() {
                                    _daysError = null;
                                    on ? _days.add(day) : _days.remove(day);
                                  }),
                                );
                              },
                            ),
                        ],
                      ),
                      if (_daysError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: NexSpacing.xs),
                          child: Text(
                            _daysError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                  HabitPlan.every => stepper(
                    id: 'habit-every',
                    value: _every,
                    min: 2,
                    max: 30,
                    step: 1,
                    onChanged: (v) => setState(() => _every = v),
                    label: strings(context, 'everyN', {'n': _every}),
                  ),
                },
                section('whatCounts'),
                AdaptiveSegments<bool>(
                  key: const ValueKey('habit-field-goal'),
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(strings(context, 'goalTick')),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.pin_outlined),
                      label: Text(strings(context, 'goalAmount')),
                    ),
                  ],
                  selected: {_counted},
                  onSelectionChanged: (value) =>
                      setState(() => _counted = value.first),
                ),
                if (_counted) ...[
                  const SizedBox(height: NexSpacing.md),
                  stepper(
                    id: 'habit-goal',
                    value: _goal,
                    min: 2,
                    max: 9999,
                    step: _goal >= 40
                        ? 10
                        : _goal >= 12
                        ? 5
                        : 1,
                    onChanged: (v) => setState(() => _goal = v),
                    label: nexDigits('$_goal', persian: persian),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  NexTextField(
                    key: const ValueKey('habit-field-unit'),
                    controller: _unit,
                    textCapitalization: TextCapitalization.none,
                    decoration: InputDecoration(
                      labelText: strings(context, 'unitLabel'),
                      hintText: strings(context, 'unitHint'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: NexSpacing.lg),
                NexTextField(
                  key: const ValueKey('habit-field-note'),
                  controller: _note,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: strings(context, 'noteLabel'),
                    hintText: strings(context, 'noteHint'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: NexSpacing.lg),
                FilledButton(
                  key: const ValueKey('habit-save'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: hue.deep,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _saving ? null : () => _save(),
                  child: _saving
                      ? const NexInlineSpinner(size: 20)
                      : Text(l10n.save),
                ),
                const SizedBox(height: NexSpacing.sm),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          await _draft.clear();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                  child: Text(l10n.cancel),
                ),
                const SizedBox(height: NexSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
