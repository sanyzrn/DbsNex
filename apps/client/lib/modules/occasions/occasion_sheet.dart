import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'adaptive_segments.dart';
import 'draft_guard.dart';
import 'form_draft.dart';
import 'module.dart';
import 'occasion_math.dart';
import 'occasion_model.dart';
import 'occasion_reminders.dart';
import 'occasion_text.dart';

/// Adds an occasion, or edits one. Saving writes the whole record over the
/// old one (keeping fields this version does not know), then renews its
/// reminders. What was typed survives a swipe away, as a draft.
Future<void> showOccasionSheet(
  BuildContext context,
  NexModuleStore store, {
  Occasion? occasion,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) => _OccasionSheet(store: store, occasion: occasion),
);

/// Whole digits from what was typed — Persian and Arabic-Indic digits
/// included — or null if it is not a plain number.
int? occasionNumber(String text) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final buffer = StringBuffer();
  for (final unit in text.trim().runes) {
    final char = String.fromCharCode(unit);
    final p = persian.indexOf(char);
    final a = arabic.indexOf(char);
    buffer.write(p >= 0 ? p : (a >= 0 ? a : char));
  }
  final ascii = buffer.toString();
  return RegExp(r'^\d{1,5}$').hasMatch(ascii) ? int.parse(ascii) : null;
}

class _OccasionSheet extends StatefulWidget {
  const _OccasionSheet({required this.store, required this.occasion});

  final NexModuleStore store;
  final Occasion? occasion;

  @override
  State<_OccasionSheet> createState() => _OccasionSheetState();
}

class _OccasionSheetState extends State<_OccasionSheet> {
  late final TextEditingController _title;
  late final TextEditingController _day;
  late final TextEditingController _year;
  late final TextEditingController _note;
  late OccasionKind _kind;
  late OccasionCalendar _calendar;
  late int _month;
  late bool _yearUnknown;
  // A new occasion asks what, which kind and which day; the year (for an
  // age), a note and a reminder wait behind one button. Correcting a saved
  // one opens them.
  late bool _more;
  late bool _nextDay;
  late bool _remind;
  late int _remindDays;
  late int _remindMinutes;

  late final FormDraft _draft;
  bool _restoring = true;
  bool _saving = false;
  late final String _recordId = widget.occasion?.id ?? widget.store.newId();
  String? _titleError, _dayError, _yearError;

  bool get _editing => widget.occasion != null;

  @override
  void initState() {
    super.initState();
    final o = widget.occasion;
    _title = TextEditingController(text: o?.title ?? '');
    _day = TextEditingController(text: o != null && o.valid ? '${o.day}' : '');
    _year = TextEditingController(text: o?.year == null ? '' : '${o!.year}');
    _note = TextEditingController(text: o?.note ?? '');
    _kind = o?.kind ?? OccasionKind.birthday;
    _yearUnknown = o != null ? o.year == null : true;
    _more = o != null;
    _nextDay = o?.nextDayInShortYears ?? false;
    _remind = o?.remindDays != null;
    _remindDays = o?.remindDays ?? 1;
    _remindMinutes = o?.remindMinutes ?? Occasion.defaultRemindMinutes;
    _draft = FormDraft(
      widget.store,
      'occasion:${o?.id ?? 'new'}',
      o?.toJson() ?? const {},
      {'title': _title, 'day': _day, 'year': _year, 'note': _note},
      () => {
        'recordId': _recordId,
        'kind': _kind.name,
        'calendar': _calendar.name,
        'month': _month,
        'yearUnknown': _yearUnknown,
        'more': _more,
        'nextDay': _nextDay,
        'remind': _remind,
        'remindDays': _remindDays,
        'remindMinutes': _remindMinutes,
      },
    );
    unawaited(_restoreDraft());
  }

  bool _calendarReady = false;

  /// A new occasion starts in the calendar the person is reading — which is
  /// known only once the sheet is in the tree, not in `initState`.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_calendarReady) return;
    _calendarReady = true;
    final o = widget.occasion;
    _calendar =
        o?.calendar ??
        (NexModuleCalendar.solarOf(context)
            ? OccasionCalendar.jalali
            : OccasionCalendar.gregorian);
    _month = o != null && o.valid
        ? o.month
        : dateIn(_calendar, DateTime.now()).month;
  }

  Future<void> _restoreDraft() async {
    final body = await _draft.load();
    if (!mounted) return;
    if (body != null) {
      _draft.apply(body);
      _kind =
          OccasionKind.values
              .where((k) => k.name == body['kind'])
              .firstOrNull ??
          _kind;
      _calendar = body['calendar'] == 'jalali'
          ? OccasionCalendar.jalali
          : OccasionCalendar.gregorian;
      final month = body['month'];
      if (month is int && month >= 1 && month <= 12) _month = month;
      _yearUnknown = body['yearUnknown'] == true;
      _more = _more || body['more'] == true;
      _nextDay = body['nextDay'] == true;
      _remind = body['remind'] == true;
      final days = body['remindDays'];
      if (days is int && days >= 0 && days <= 30) _remindDays = days;
      final minutes = body['remindMinutes'];
      if (minutes is int && minutes >= 0 && minutes < 1440) {
        _remindMinutes = minutes;
      }
    }
    _draft.start();
    setState(() => _restoring = false);
  }

  @override
  void dispose() {
    _draft.close();
    _title.dispose();
    _day.dispose();
    _year.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await nexPickModuleDate(
      context,
      initial: now,
      first: DateTime(1900),
      last: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    final d = dateIn(_calendar, picked);
    setState(() {
      _day.text = '${d.day}';
      _month = d.month;
      if (!_yearUnknown) _year.text = '${d.year}';
      _dayError = _yearError = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await nexPickModuleTime(
      context,
      initial: TimeOfDay(
        hour: _remindMinutes ~/ 60,
        minute: _remindMinutes % 60,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _remindMinutes = picked.hour * 60 + picked.minute);
    }
  }

  /// The record for what is typed, or null with the errors shown.
  Occasion? _build() {
    final strings = occasionsStrings;
    final title = _title.text.trim();
    String? titleError, dayError, yearError;
    if (title.isEmpty) titleError = strings(context, 'titleRequired');
    final day = occasionNumber(_day.text);
    if (day == null || !dayExistsSomeYear(_calendar, _month, day)) {
      dayError = strings(context, 'dayInvalid');
    }
    int? year;
    if (!_yearUnknown) {
      year = occasionNumber(_year.text);
      if (year == null || year < 1) {
        yearError = strings(context, 'yearInvalid');
      } else if (year > calendarYearOf(_stub(), DateTime.now())) {
        yearError = strings(context, 'yearFuture');
      } else if (day != null &&
          dayError == null &&
          !dayExistsIn(_calendar, year, _month, day)) {
        yearError = strings(context, 'yearDayInvalid');
      }
    }
    if (titleError != null || dayError != null || yearError != null) {
      setState(() {
        _titleError = titleError;
        _dayError = dayError;
        _yearError = yearError;
      });
      return null;
    }
    final old = widget.occasion;
    return Occasion(
      id: _recordId,
      title: title,
      kind: _kind,
      calendar: _calendar,
      month: _month,
      day: day!,
      year: _yearUnknown ? null : year,
      nextDayInShortYears: canFallShort(_calendar, _month, day) && _nextDay,
      note: _note.text.trim(),
      favorite: old?.favorite ?? false,
      muted: old?.muted ?? false,
      archived: old?.archived ?? false,
      remindDays: _remind ? _remindDays : null,
      remindMinutes: _remindMinutes,
      createdAt: old?.createdAt ?? DateTime.now(),
    );
  }

  /// An occasion only to ask which year of its calendar today falls in.
  Occasion _stub() => Occasion(
    id: '',
    title: '',
    kind: _kind,
    calendar: _calendar,
    month: 1,
    day: 1,
    createdAt: DateTime.now(),
  );

  Future<void> _save() async {
    if (_saving) return;
    final occasion = _build();
    if (occasion == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final failedText = occasionsStrings(context, 'saveError');
    final remindFailed = occasionsStrings(context, 'remindFailed');
    final l10n = AppLocalizations.of(context);
    final reminderBody = occasionNotificationBody(context, occasion);
    try {
      final prior = await widget.store.get('occasion', occasion.id);
      await widget.store.put('occasion', occasion.id, {
        ...?prior,
        ...occasion.toJson(),
      });
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failedText)));
      if (mounted) setState(() => _saving = false);
      return;
    }
    try {
      await _draft.clear();
    } catch (_) {
      /* The saved record stays authoritative. */
    }
    var remindersOk = true;
    try {
      remindersOk = await armOccasionReminders(
        widget.store,
        occasion,
        now: DateTime.now(),
        title: l10n.cycleNotifyTitle,
        body: reminderBody,
      );
    } catch (_) {
      remindersOk = false;
    }
    if (!mounted) return;
    if (!remindersOk && occasion.remindDays != null) {
      messenger.showSnackBar(SnackBar(content: Text(remindFailed)));
    }
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_restoring) _draft.changed();
    final strings = occasionsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final solar = _calendar == OccasionCalendar.jalali;
    final dayValue = occasionNumber(_day.text);
    final short = dayValue != null && canFallShort(_calendar, _month, dayValue);
    final l10n = AppLocalizations.of(context);
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
                  strings(context, _editing ? 'editOccasion' : 'newOccasion'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: NexSpacing.md),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    for (final kind in OccasionKind.values)
                      ChoiceChip(
                        key: ValueKey('occasion-kind-${kind.name}'),
                        avatar: Icon(occasionIcon(kind), size: 18),
                        label: Text(occasionKindLabel(context, kind)),
                        selected: _kind == kind,
                        onSelected: (_) => setState(() => _kind = kind),
                      ),
                  ],
                ),
                const SizedBox(height: NexSpacing.md),
                NexAutoDirection(
                  controller: _title,
                  builder: (context, _) => TextField(
                    key: const ValueKey('occasion-field-title'),
                    controller: _title,
                    autofocus: !_editing,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) {
                      if (_titleError != null) {
                        setState(() => _titleError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: strings(context, 'titleLabel'),
                      hintText: strings(context, 'titleHint'),
                      errorText: _titleError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                Text(
                  strings(context, 'calendarLabel'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NexSpacing.xs),
                AdaptiveSegments<OccasionCalendar>(
                  key: const ValueKey('occasion-field-calendar'),
                  segments: [
                    ButtonSegment(
                      value: OccasionCalendar.jalali,
                      label: Text(strings(context, 'jalali')),
                    ),
                    ButtonSegment(
                      value: OccasionCalendar.gregorian,
                      label: Text(strings(context, 'gregorian')),
                    ),
                  ],
                  selected: {_calendar},
                  onSelectionChanged: (value) => setState(() {
                    _calendar = value.first;
                    _dayError = _yearError = null;
                  }),
                ),
                const SizedBox(height: NexSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 84,
                      child: TextField(
                        key: const ValueKey('occasion-field-day'),
                        controller: _day,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        onChanged: (_) {
                          if (_dayError != null) {
                            setState(() => _dayError = null);
                          } else {
                            setState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          labelText: strings(context, 'dayLabel'),
                          errorText: _dayError == null ? null : '',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: NexSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        borderRadius: nexDropdownRadius,
                        dropdownColor: nexDropdownColor(context),
                        key: const ValueKey('occasion-field-month'),
                        initialValue: _month,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: strings(context, 'monthLabel'),
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (var m = 1; m <= 12; m++)
                            DropdownMenuItem(
                              value: m,
                              child: Text(
                                nexModuleMonthName(
                                  context,
                                  solar: solar,
                                  month: m,
                                ),
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _month = value ?? _month;
                          _dayError = _yearError = null;
                        }),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('occasion-pick-date'),
                      tooltip: strings(context, 'pickDate'),
                      icon: const Icon(Icons.calendar_month_outlined),
                      onPressed: _pickDate,
                    ),
                  ],
                ),
                if (_dayError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: NexSpacing.xs),
                    child: Text(
                      _dayError!,
                      key: const ValueKey('occasion-day-error'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                if (short) ...[
                  const SizedBox(height: NexSpacing.md),
                  Text(
                    strings(context, 'leapTitle'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: NexSpacing.xs),
                  AdaptiveSegments<bool>(
                    key: const ValueKey('occasion-field-leap'),
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(strings(context, 'leapLast')),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(strings(context, 'leapNext')),
                      ),
                    ],
                    selected: {_nextDay},
                    onSelectionChanged: (value) =>
                        setState(() => _nextDay = value.first),
                  ),
                ],
                const SizedBox(height: NexSpacing.md),
                NexMoreDetails(
                  toggleKey: const ValueKey('occasion-more-toggle'),
                  open: _more,
                  onChanged: (open) => setState(() => _more = open),
                  title: strings(context, 'moreDetails'),
                  hint: strings(context, 'moreDetailsHint'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: NexSpacing.sm),
                      CheckboxListTile(
                        key: const ValueKey('occasion-year-unknown'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(strings(context, 'yearUnknown')),
                        value: _yearUnknown,
                        onChanged: (value) => setState(() {
                          _yearUnknown = value ?? false;
                          _yearError = null;
                        }),
                      ),
                      if (!_yearUnknown)
                        TextField(
                          key: const ValueKey('occasion-field-year'),
                          controller: _year,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          onChanged: (_) {
                            if (_yearError != null) {
                              setState(() => _yearError = null);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: strings(context, 'yearLabel'),
                            errorText: _yearError,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      const SizedBox(height: NexSpacing.md),
                      NexTextField(
                        key: const ValueKey('occasion-field-note'),
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
                      const SizedBox(height: NexSpacing.sm),
                      SwitchListTile(
                        key: const ValueKey('occasion-remind-switch'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(strings(context, 'remindLabel')),
                        value: _remind,
                        onChanged: (value) => setState(() => _remind = value),
                      ),
                      if (_remind) ...[
                        Wrap(
                          spacing: NexSpacing.sm,
                          runSpacing: NexSpacing.sm,
                          children: [
                            for (final (days, key) in const [
                              (0, 'remindOnDay'),
                              (1, 'remindOneBefore'),
                              (3, 'remindThreeBefore'),
                              (7, 'remindWeekBefore'),
                            ])
                              ChoiceChip(
                                key: ValueKey('occasion-remind-$days'),
                                label: Text(strings(context, key)),
                                selected: _remindDays == days,
                                onSelected: (_) =>
                                    setState(() => _remindDays = days),
                              ),
                            ActionChip(
                              key: const ValueKey('occasion-remind-time'),
                              avatar: const Icon(Icons.schedule, size: 18),
                              label: Text(
                                strings(context, 'remindAt', {
                                  'time': occasionTimeText(
                                    context,
                                    _remindMinutes,
                                  ),
                                }),
                              ),
                              onPressed: _pickTime,
                            ),
                          ],
                        ),
                        const SizedBox(height: NexSpacing.xs),
                        Text(
                          strings(context, 'remindNote'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: NexSpacing.lg),
                FilledButton(
                  key: const ValueKey('occasion-save'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _saving ? null : () => unawaited(_save()),
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
