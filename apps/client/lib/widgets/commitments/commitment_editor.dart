part of '../commitments_sheet.dart';

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
  }) => Navigator.of(context).push<bool>(
    // A page, not a sheet: this is where money and medicine get their
    // schedule, and it has the room to say so. Swiping back from the edge
    // is the ordinary back, and asks first when something has changed.
    NexPageRoute<bool>(
      builder: (_) => CommitmentEditor(services: services, existing: existing),
    ),
  );

  @override
  State<CommitmentEditor> createState() => _CommitmentEditorState();
}

class _CommitmentEditorState extends State<CommitmentEditor>
    with NexDraftGuard<CommitmentEditor> {
  String get _draftKey => 'commitment-${widget.existing?.id ?? 'new'}';
  late Map<String, dynamic> _details = {
    ...?widget.existing?.details,
    if (widget.existing == null) 'solar': widget.services.solarCalendar,
  };

  /// Whether the editor differs from how it opened. Compared, not flagged:
  /// any rebuild used to count as an edit, so closing an untouched editor
  /// still asked to discard changes nobody had made.
  bool _dirty = false;
  late final String _baseline;
  @override
  bool get hasUnsavedChanges => _dirty;
  @override
  void discardDraft() => widget.services.editorDrafts?.clear(_draftKey);

  Map<String, dynamic> get _form => {
    'details': _details,
    'title': _title.text,
    'cadence': _cadence.index,
    'every': _every,
    'due': _dueAt.toIso8601String(),
    'lead': _lead?.inSeconds,
    'notify': _notify,
    'window': _window,
    'start': _windowStart,
    'end': _windowEnd,
  };

  /// The form as a comparable string: keys in order, empty values and the
  /// defaults a field fills in by itself left out, so touching a field and
  /// putting it back is no change.
  String _fingerprint() {
    Object? canonical(Object? value) => switch (value) {
      Map() => {
        for (final key in value.keys.map((k) => '$k').toList()..sort())
          if (value[key] != null) key: canonical(value[key]),
      },
      List() => [for (final item in value) canonical(item)],
      _ => value,
    };
    final details = {..._details};
    if (details['invalidAmount'] == false) details.remove('invalidAmount');
    details['currency'] ??= 'IRT';
    return jsonEncode(
      canonical({..._form, 'details': details, 'title': _title.text.trim()}),
    );
  }

  void _snapshot() {
    final dirty = _fingerprint() != _baseline;
    if (dirty) {
      widget.services.editorDrafts?.write(_draftKey, _form);
    } else {
      discardDraft();
    }
    if (dirty != _dirty) {
      // The back gesture reads this at build time; typing in the title does
      // not rebuild the editor by itself.
      super.setState(() => _dirty = dirty);
    }
  }

  @override
  void initState() {
    super.initState();
    _baseline = _fingerprint();
    final d = widget.services.editorDrafts?.read(_draftKey);
    if (d != null) {
      _details = Map<String, dynamic>.from(d['details'] as Map? ?? _details);
      _title.text = d['title'] as String;
      _cadence = NexCadence.values[d['cadence'] as int];
      _every = d['every'] as int;
      _dueAt = DateTime.parse(d['due'] as String);
      _lead = d['lead'] == null ? null : Duration(seconds: d['lead'] as int);
      _notify = d['notify'] as bool;
      _window = d['window'] as bool;
      _windowStart = d['start'] as int;
      _windowEnd = d['end'] as int;
      _dirty = _fingerprint() != _baseline;
    }
    _title.addListener(_snapshot);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (!_saving) _snapshot();
  }

  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late NexCadence _cadence = widget.existing?.cadence ?? NexCadence.months;
  late int _every = widget.existing?.every ?? 1;
  late DateTime _dueAt = widget.existing?.dueAt ?? _defaultDue(DateTime.now());
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
    _title.removeListener(_snapshot);
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await nexPickDate(
      context,
      solar: widget.services.solarCalendar,
      initial: _dueAt,
      first: DateTime(2020),
      last: DateTime(2100),
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
    if (_details['invalidAmount'] == true) {
      nexShowBanner(
        context,
        message: nexLabel(
          context,
          'Enter a valid amount with up to two decimal places.',
          'مبلغ معتبر با حداکثر دو رقم اعشار وارد کنید.',
        ),
      );
      return;
    }
    _details = {
      ..._details,
      'currency': _details['currency'] ?? 'IRT',
      'anchor':
          widget.existing == null ||
              widget.existing!.dueAt != _dueAt ||
              widget.existing!.cadence != _cadence ||
              widget.existing!.every != _every
          ? _dueAt.toIso8601String()
          : _details['anchor'] ?? _dueAt.toIso8601String(),
      if (widget.existing?.dueAt != _dueAt) 'scheduledDue': null,
    };
    setState(() => _saving = true);
    final now = DateTime.now();
    final existing = widget.existing;
    final commitment = existing == null
        ? NexCommitment(
            id: newUuidV7(),
            title: title,
            details: _details,
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
            details: _details,
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
    try {
      await widget.services.saveCommitment(commitment);
      discardDraft();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).captureFailed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Only the hourly cadence gets a waking window, because it is the only
    // one fine enough to fire while somebody is asleep. Offering it on a
    // yearly renewal would be offering to move a date nobody asked to move.
    final hourly = _cadence == NexCadence.hours;
    final canSave = _title.text.trim().isNotEmpty && !_saving;
    return guardDraft(
      Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.cancel,
            onPressed: requestDiscard,
            icon: const Icon(Icons.close),
          ),
          title: Text(
            widget.existing == null ? l10n.commitmentAdd : l10n.commitmentEdit,
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: NexSpacing.sm),
              child: FilledButton(
                onPressed: canSave ? () => unawaited(_save()) : null,
                child: Text(l10n.save),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            NexSpacing.xl + nexBottomInset(context),
          ),
          children: [
            _SectionLabel(nexLabel(context, 'What', 'چه چیزی')),
            if (widget.existing == null)
              Wrap(
                spacing: 6,
                children: [
                  for (final (id, en, fa, cadence) in [
                    (
                      'subscription',
                      'Subscription',
                      'اشتراک',
                      NexCadence.months,
                    ),
                    ('installment', 'Installment', 'قسط', NexCadence.months),
                    (
                      'routine',
                      'Recurring task',
                      'کار دوره‌ای',
                      NexCadence.weeks,
                    ),
                    ('habit', 'Habit', 'عادت', NexCadence.days),
                  ])
                    ActionChip(
                      label: Text(nexLabel(context, en, fa)),
                      onPressed: () => setState(() {
                        _title.text = nexLabel(context, en, fa);
                        _cadence = cadence;
                        _every = 1;
                        _lead = id == 'subscription' || id == 'installment'
                            ? const Duration(days: 2)
                            : Duration.zero;
                        _details = {..._details, 'template': id};
                      }),
                    ),
                ],
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
                // Not focused on open. The page leads with the templates,
                // and a keyboard that comes up by itself covers half of the
                // form before anyone has decided what to fill in.
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.commitmentTitleLabel,
                  hintText: l10n.commitmentTitleHint,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: NexSpacing.lg),
            _SectionLabel(nexLabel(context, 'When', 'چه وقت')),
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
                style: Theme.of(context).textTheme.bodyLarge,
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
                style: Theme.of(context).textTheme.bodyLarge,
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
            RecurringOptions(
              cadence: _cadence,
              value: _details,
              onChanged: (v) => setState(() => _details = v),
            ),
            const SizedBox(height: NexSpacing.lg),
            _SectionLabel(nexLabel(context, 'Reminders', 'یادآوری')),
            // The field the whole feature turns on, and the one that is
            // usually left alone.
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.commitmentLead),
              subtitle: Text(
                _lead == null
                    ? l10n.commitmentLeadAuto(
                        nexRelativeSpan(l10n, nexDefaultLead(_cadence, _every)),
                      )
                    : nexRelativeSpan(l10n, _lead!),
              ),
              trailing: DropdownButton<int>(
                value: _lead?.inHours ?? -1,
                underline: const SizedBox.shrink(),
                style: Theme.of(context).textTheme.bodyLarge,
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
                      ? nexDigits(
                          '${_clock(_windowStart)} – ${_clock(_windowEnd)}',
                          persian:
                              Localizations.localeOf(context).languageCode ==
                              'fa',
                        )
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
            const SizedBox(height: NexSpacing.lg),
            _SectionLabel(nexLabel(context, 'Attached', 'پیوست‌ها')),
            RecurringAttachments(
              services: widget.services,
              details: _details,
              onChanged: (details) => setState(() {
                _details = details;
                _snapshot();
              }),
            ),
            const SizedBox(height: NexSpacing.xl),
            // Save again at the end of the form, where the thumb is.
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: canSave ? () => unawaited(_save()) : null,
              icon: const Icon(Icons.check),
              label: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  String _dateLabel(DateTime when) => nexDisplayDate(
    when,
    solar: widget.services.solarCalendar,
    persian: AppLocalizations.of(context).localeName == 'fa',
    time: true,
  );
}

/// The heading over one part of the form.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.xs),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
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
    subtitle: Text(
      nexDigits(
        _CommitmentEditorState._clock(minutes),
        persian: Localizations.localeOf(context).languageCode == 'fa',
      ),
    ),
    onTap: () async {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      );
      if (picked != null) onChanged(picked.hour * 60 + picked.minute);
    },
  );
}
