import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/cycle_reminders.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/nex_time_picker.dart';
import 'cycle/cycle_calendar.dart';
import 'cycle/cycle_day_sheet.dart';
import 'cycle/cycle_format.dart';
import 'cycle/cycle_report_screen.dart';
import 'cycle/cycle_ring.dart';
import 'cycle/cycle_settings_sheet.dart';

/// «Cycle» — the menstrual cycle assistant.
///
/// One page: where in the cycle today is, one button for the thing that
/// happens (a period starting or ending), the day's log, a month calendar,
/// what has been learned, and the past periods to correct. Everything is on
/// this phone and in its backups, in tables nothing else reads.
class CycleScreen extends StatefulWidget {
  const CycleScreen({
    super.key,
    required this.services,
    required this.preferences,
    this.today,
  });

  final NexServices services;
  final NexPreferences preferences;

  /// For tests; the real today otherwise.
  final DateTime? today;

  @override
  State<CycleScreen> createState() => _CycleScreenState();
}

class _CycleScreenState extends State<CycleScreen> {
  bool _loading = true;
  List<CyclePeriod> _periods = const [];
  CyclePrediction? _prediction;
  Set<CycleDate> _logged = const {};
  CycleDayLog? _todayLog;
  List<CyclePattern> _patterns = const [];
  late (DateTime, DateTime) _month;

  NexServices get _services => widget.services;
  DateTime get _today => DateUtils.dateOnly(widget.today ?? DateTime.now());
  bool get _solar => _services.solarCalendar;

  @override
  void initState() {
    super.initState();
    final t = _today;
    // Wide enough for either calendar's month around today; the calendar
    // narrows it as soon as it is turned.
    _month = (
      t.subtract(const Duration(days: 40)),
      t.add(const Duration(days: 40)),
    );
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final periods = await _services.cyclePeriods();
    final prediction = await _services.cyclePrediction(today: _today);
    final days = await _services.cycleDays(_month.$1, _month.$2);
    final todayLog = (await _services.cycleDays(_today, _today)).firstOrNull;
    final allLogs = await _services.cycleDays(DateTime(2000), _today);
    if (!mounted) return;
    setState(() {
      _periods = periods;
      _prediction = prediction;
      _logged = {for (final d in days) d.day};
      _todayLog = todayLog;
      _patterns = CyclePatterns.find(periods: periods, logs: allLogs);
      _loading = false;
    });
  }

  Future<void> _changed() async {
    await _reload();
    if (!mounted) return;
    await CycleReminders.apply(
      context: context,
      services: _services,
      preferences: widget.preferences,
    );
  }

  CyclePeriod? get _open {
    for (final p in _periods.reversed) {
      if (p.isOpen) return p;
    }
    return null;
  }

  Future<void> _startOn(DateTime day) async {
    await _services.cycleStartPeriod(day);
    await _changed();
  }

  Future<void> _endOn(DateTime day) async {
    final open = _open;
    if (open == null) return;
    await _services.cycleEndPeriod(open.id, day);
    await _changed();
  }

  Future<DateTime?> _pickPastDay({DateTime? initial, DateTime? first}) =>
      nexPickDate(
        context,
        initial: initial ?? _today,
        first: first ?? _today.subtract(const Duration(days: 365)),
        last: _today,
        solar: _solar,
      );

  Future<void> _openDay(DateTime day) async {
    final saved = await CycleDaySheet.show(
      context,
      services: _services,
      day: day,
      periods: _periods,
    );
    if (saved) await _changed();
  }

  Future<void> _settings() async {
    final deleted = await CycleSettingsSheet.show(
      context,
      services: _services,
      preferences: widget.preferences,
    );
    if (deleted) {
      setState(() => _loading = true);
    }
    await _changed();
  }

  Future<void> _editPeriod(CyclePeriod period) async {
    final l10n = AppLocalizations.of(context);
    var start = period.start.local;
    DateTime? end = period.end?.local;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(l10n.cycleEditPeriod),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.cycleStart),
                trailing: Text(cycleDayMonth(context, start, solar: _solar)),
                onTap: () async {
                  final picked = await _pickPastDay(initial: start);
                  if (picked != null) setDialog(() => start = picked);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.cycleEnd),
                trailing: Text(
                  end == null
                      ? l10n.cycleOngoing
                      : cycleDayMonth(context, end!, solar: _solar),
                ),
                onTap: () async {
                  final picked = await _pickPastDay(
                    initial: end ?? start,
                    first: start,
                  );
                  if (picked != null) setDialog(() => end = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'delete'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              child: Text(l10n.cycleDeletePeriod),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (result == 'delete') {
      await _services.cycleDeletePeriod(period.id);
    } else if (result == 'save') {
      await _services.cycleUpdatePeriod(period.id, start, end);
    } else {
      return;
    }
    await _changed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cycleTitle),
        actions: [
          if (widget.preferences.cycleSetUp)
            IconButton(
              tooltip: l10n.cycleSettings,
              icon: const Icon(Icons.tune),
              onPressed: _settings,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : !widget.preferences.cycleSetUp
            ? _Welcome(
                today: _today,
                solar: _solar,
                onDone: (lastStart, period, cycle) async {
                  final prefs = widget.preferences;
                  await prefs.setCycleTypical(cycle: cycle, period: period);
                  await prefs.setCycleSetUp(true);
                  if (lastStart != null) {
                    final started = await _services.cycleStartPeriod(lastStart);
                    final end = lastStart.add(
                      Duration(days: (period ?? prefs.cycleTypicalPeriod) - 1),
                    );
                    if (end.isBefore(_today)) {
                      await _services.cycleEndPeriod(started.id, end);
                    }
                  }
                  await _changed();
                },
              )
            : _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rose = cyclePeriodColor(theme.brightness);
    final teal = cycleFertileColor(theme.brightness);
    final mode = widget.preferences.cycleMode;
    // Out of the modes that predict, nothing below shows a prediction: no
    // ring, no range, no alerts, no expected days on the calendar.
    final p = mode.predicts ? _prediction : null;
    final conceive = mode == CycleMode.conceive;
    final pregnancy = mode == CycleMode.pregnant
        ? CyclePregnancy(
            lastPeriod:
                widget.preferences.cyclePregnancyStart ??
                _prediction?.lastStart ??
                CycleDate.of(_today),
            today: CycleDate.of(_today),
          )
        : null;
    final open = _open;
    String digits(Object v) => cycleDigits(context, v);
    String day(CycleDate d) => cycleDayMonth(context, d.local, solar: _solar);

    final (headline, caption) = switch (p) {
      null when !mode.predicts => (
        cycleModeLabel(l10n, mode),
        l10n.cyclePredictionsOff,
      ),
      null => (l10n.cycleNothingLogged, l10n.cycleWelcomeBody),
      _ when p.inPeriod => (
        l10n.cycleDayOfPeriod(digits(p.cycleDay)),
        l10n.cycleDayOfCycle(digits(p.cycleDay)),
      ),
      // Trying to conceive: the fertile window leads, and the next period
      // is the line under it.
      _
          when conceive &&
              !p.fertile.start.isAfter(p.today) &&
              !p.fertile.end.isBefore(p.today) =>
        (l10n.cycleFertileToday, l10n.cycleOvulationOn(day(p.ovulation))),
      _ when conceive && p.fertile.start.isAfter(p.today) => (
        digits(l10n.cycleUntilFertile(p.fertile.start.daysSince(p.today))),
        l10n.cycleOvulationOn(day(p.ovulation)),
      ),
      _ when p.daysUntilNext > 0 => (
        digits(l10n.cycleDaysUntil(p.daysUntilNext)),
        l10n.cycleDayOfCycle(digits(p.cycleDay)),
      ),
      _ when p.daysUntilNext == 0 => (
        l10n.cycleDueToday,
        l10n.cycleDayOfCycle(digits(p.cycleDay)),
      ),
      _ => (
        digits(l10n.cycleLate(-p.daysUntilNext)),
        l10n.cycleDayOfCycle(digits(p.cycleDay)),
      ),
    };

    final todaySummary = _todayLog == null
        ? l10n.cycleNothingLogged
        : [
            if (_todayLog!.flow != null) cycleFlowLabel(l10n, _todayLog!.flow),
            if (_todayLog!.mood != null) cycleMoodLabel(l10n, _todayLog!.mood!),
            for (final s in _todayLog!.symptoms.take(3))
              cycleSymptomLabel(l10n, s),
          ].join(' · ');

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          NexSpacing.md,
          NexSpacing.xs,
          NexSpacing.md,
          NexSpacing.xl,
        ),
        children: [
          if (mode != CycleMode.normal)
            Center(
              child: ActionChip(
                key: const ValueKey('cycle-mode-chip'),
                avatar: Icon(
                  mode == CycleMode.pregnant
                      ? Icons.child_friendly_outlined
                      : Icons.tune,
                  size: 18,
                ),
                label: Text(cycleModeLabel(l10n, mode)),
                onPressed: _settings,
              ),
            ),
          if (pregnancy != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.xl),
              child: CycleProgressRing(
                fraction: pregnancy.fraction,
                color: rose,
                headline: l10n.cyclePregnancyWeek(
                  digits(pregnancy.weeks),
                  digits(pregnancy.days),
                ),
                caption: l10n.cycleDueDate(day(pregnancy.dueDate)),
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            Text(
              '${l10n.cycleTrimester(digits(pregnancy.trimester))} · '
              '${digits(l10n.cycleDaysToGo(pregnancy.daysToGo.clamp(0, 400)))}',
              key: const ValueKey('cycle-pregnancy-line'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: NexSpacing.md),
          ] else if (p != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.xl),
              child: CycleRing(
                prediction: p,
                headline: headline,
                caption: caption,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(NexSpacing.lg),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          if (p != null) ...[
            const SizedBox(height: NexSpacing.sm),
            if (!p.inPeriod)
              Text(
                l10n.cycleLikelyBetween(day(p.nextEarliest), day(p.nextLatest)),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            Text(
              switch (p.confidence) {
                CycleConfidence.low => l10n.cycleConfidenceLow,
                CycleConfidence.medium => l10n.cycleConfidenceMedium,
                CycleConfidence.high => l10n.cycleConfidenceHigh,
              },
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (!p.fertile.end.isBefore(p.today))
              Padding(
                padding: const EdgeInsets.only(top: NexSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.spa_outlined, size: 16, color: teal),
                    const SizedBox(width: NexSpacing.xs),
                    Flexible(
                      child: Text(
                        '${l10n.cycleFertileNow}: ${day(p.fertile.start)} – ${day(p.fertile.end)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: teal),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (pregnancy == null) ...[
            const SizedBox(height: NexSpacing.md),
            FilledButton.icon(
              key: const ValueKey('cycle-primary'),
              style: FilledButton.styleFrom(
                backgroundColor: rose,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => unawaited(
                open != null && (p?.inPeriod ?? false)
                    ? _endOn(_today)
                    : _startOn(_today),
              ),
              icon: Icon(
                open != null && (p?.inPeriod ?? false)
                    ? Icons.check_circle_outline
                    : Icons.water_drop_outlined,
              ),
              label: Text(
                open != null && (p?.inPeriod ?? false)
                    ? l10n.cyclePeriodEnded
                    : l10n.cyclePeriodStarted,
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () async {
                  final picked = await _pickPastDay(
                    first: open != null && (p?.inPeriod ?? false)
                        ? open.start.local
                        : null,
                  );
                  if (picked == null) return;
                  if (open != null && (p?.inPeriod ?? false)) {
                    await _endOn(picked);
                  } else {
                    await _startOn(picked);
                  }
                },
                child: Text(l10n.cycleAnotherDay),
              ),
            ),
          ],
          for (final alert in p?.alerts ?? const <CycleAlert>{})
            Card(
              margin: const EdgeInsets.only(bottom: NexSpacing.sm),
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(NexSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: NexSpacing.sm),
                    Expanded(
                      child: Text(
                        '${cycleAlertText(l10n, alert)} ${l10n.cycleNotAdvice}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Card(
            margin: const EdgeInsets.only(bottom: NexSpacing.md),
            child: ListTile(
              key: const ValueKey('cycle-log-today'),
              leading: Icon(Icons.edit_calendar_outlined, color: rose),
              title: Text(l10n.cycleLogToday),
              subtitle: Text(
                todaySummary.isEmpty ? l10n.cycleNothingLogged : todaySummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openDay(_today),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: NexSpacing.md),
            child: Padding(
              padding: const EdgeInsets.all(NexSpacing.sm),
              child: CycleCalendar(
                periods: _periods,
                prediction: p,
                logged: _logged,
                solar: _solar,
                today: _today,
                onDay: _openDay,
                onMonth: (from, to) {
                  _month = (from, to);
                  unawaited(_reload());
                },
              ),
            ),
          ),
          if (p != null) ...[
            Text(l10n.cycleInsights, style: theme.textTheme.titleSmall),
            const SizedBox(height: NexSpacing.sm),
            Row(
              children: [
                _Stat(
                  label: l10n.cycleAverageCycle,
                  value: digits(l10n.cycleDays(p.averageCycle)),
                ),
                const SizedBox(width: NexSpacing.sm),
                _Stat(
                  label: l10n.cycleLegendPeriod,
                  value: digits(l10n.cycleDays(p.averagePeriod)),
                ),
                const SizedBox(width: NexSpacing.sm),
                _Stat(
                  label: l10n.cycleCyclesCounted,
                  value: digits(p.cyclesUsed),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.md),
          ],
          Text(l10n.cyclePatterns, style: theme.textTheme.titleSmall),
          const SizedBox(height: NexSpacing.xs),
          if (_patterns.isEmpty)
            Text(
              l10n.cyclePatternsEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (final pattern in _patterns.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: NexSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.insights_outlined, size: 18, color: teal),
                    const SizedBox(width: NexSpacing.sm),
                    Expanded(child: Text(cyclePatternText(context, pattern))),
                  ],
                ),
              ),
          const SizedBox(height: NexSpacing.sm),
          Card(
            margin: const EdgeInsets.only(bottom: NexSpacing.md),
            child: ListTile(
              key: const ValueKey('cycle-report'),
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(l10n.cycleReport),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                NexPageRoute<void>(
                  builder: (_) => CycleReportScreen(
                    services: _services,
                    preferences: widget.preferences,
                  ),
                ),
              ),
            ),
          ),
          if (_periods.isNotEmpty) ...[
            Text(l10n.cycleHistory, style: theme.textTheme.titleSmall),
            for (final period in _periods.reversed.take(12))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.water_drop, color: rose, size: 20),
                title: Text(
                  period.end == null
                      ? '${day(period.start)} – ${l10n.cycleOngoing}'
                      : '${day(period.start)} – ${day(period.end!)}',
                ),
                subtitle: period.length == null
                    ? null
                    : Text(digits(l10n.cycleDays(period.length!))),
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => _editPeriod(period),
              ),
            const SizedBox(height: NexSpacing.md),
          ],
          _Footnote(
            icon: Icons.health_and_safety_outlined,
            text: l10n.cycleDisclaimer,
          ),
          if (pregnancy != null)
            _Footnote(
              icon: Icons.child_friendly_outlined,
              text: l10n.cyclePregnancyNote,
            ),
          _Footnote(icon: Icons.lock_outline, text: l10n.cyclePrivacy),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(NexSpacing.sm + 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: theme.textTheme.titleMedium),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three opening questions, each with "I don't know".
class _Welcome extends StatefulWidget {
  const _Welcome({
    required this.today,
    required this.solar,
    required this.onDone,
  });

  final DateTime today;
  final bool solar;
  final Future<void> Function(DateTime? lastStart, int? period, int? cycle)
  onDone;

  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> {
  DateTime? _lastStart;
  int _period = 5;
  int _cycle = 28;
  bool _periodKnown = true;
  bool _cycleKnown = true;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rose = cyclePeriodColor(theme.brightness);
    Widget question(String text) => Padding(
      padding: const EdgeInsets.only(top: NexSpacing.lg, bottom: NexSpacing.xs),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    Widget dontKnow(bool selected, ValueChanged<bool> onChanged) => FilterChip(
      label: Text(l10n.cycleDontKnow),
      selected: selected,
      onSelected: onChanged,
    );
    return ListView(
      padding: const EdgeInsets.all(NexSpacing.lg),
      children: [
        Icon(Icons.water_drop_outlined, size: 48, color: rose),
        const SizedBox(height: NexSpacing.sm),
        Text(
          l10n.cycleWelcome,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: NexSpacing.sm),
        Text(
          l10n.cycleWelcomeBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        question(l10n.cycleAskLastStart),
        Wrap(
          spacing: NexSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('cycle-welcome-date'),
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _lastStart == null
                    ? l10n.cyclePickDate
                    : cycleDayMonth(context, _lastStart!, solar: widget.solar),
              ),
              onPressed: () async {
                final picked = await nexPickDate(
                  context,
                  initial: _lastStart ?? widget.today,
                  first: widget.today.subtract(const Duration(days: 120)),
                  last: widget.today,
                  solar: widget.solar,
                );
                if (picked != null) setState(() => _lastStart = picked);
              },
            ),
            dontKnow(
              _lastStart == null,
              (_) => setState(() => _lastStart = null),
            ),
          ],
        ),
        question(l10n.cycleAskPeriodLength),
        if (_periodKnown)
          CycleStepper(
            label: '',
            value: _period,
            min: 1,
            max: 15,
            onChanged: (v) => setState(() => _period = v),
          ),
        dontKnow(!_periodKnown, (on) => setState(() => _periodKnown = !on)),
        question(l10n.cycleAskCycleLength),
        if (_cycleKnown)
          CycleStepper(
            label: '',
            value: _cycle,
            min: 15,
            max: 60,
            onChanged: (v) => setState(() => _cycle = v),
          ),
        dontKnow(!_cycleKnown, (on) => setState(() => _cycleKnown = !on)),
        const SizedBox(height: NexSpacing.xl),
        FilledButton(
          key: const ValueKey('cycle-welcome-begin'),
          style: FilledButton.styleFrom(
            backgroundColor: rose,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await widget.onDone(
                    _lastStart,
                    _periodKnown ? _period : null,
                    _cycleKnown ? _cycle : null,
                  );
                  if (mounted) setState(() => _busy = false);
                },
          child: Text(l10n.cycleBegin),
        ),
        const SizedBox(height: NexSpacing.md),
        Text(
          l10n.cycleDisclaimer,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
