import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/nex_services.dart';
import '../../widgets/nex_dialog.dart';
import '../../widgets/nex_text_field.dart';
import 'cycle_format.dart';
import 'cycle_space.dart';

/// What happened on one day: a sheet of taps, every part optional.
///
/// Resolves to true when anything was saved, so the screen behind it knows
/// to read the day — and the prediction — again.
abstract final class CycleDaySheet {
  static Future<bool> show(
    BuildContext context, {
    required NexServices services,
    required DateTime day,
    required List<CyclePeriod> periods,
    bool fertility = false,
  }) async {
    final date = CycleDate.of(day);
    final existing =
        (await services.cycleDays(day, day)).firstOrNull ??
        CycleDayLog(day: date);
    if (!context.mounted) return false;
    final saved = await nexShowSheet<bool>(
      context: context,
      builder: (_) => CycleSheet(
        child: _DaySheet(
          services: services,
          day: day,
          initial: existing,
          periods: periods,
          fertility:
              fertility ||
              existing.temperature != null ||
              existing.ovulationTest != null ||
              existing.mucus != null,
        ),
      ),
    );
    return saved ?? false;
  }
}

class _DaySheet extends StatefulWidget {
  const _DaySheet({
    required this.services,
    required this.day,
    required this.initial,
    required this.periods,
    required this.fertility,
  });

  final NexServices services;
  final DateTime day;
  final CycleDayLog initial;
  final List<CyclePeriod> periods;

  /// Temperature, ovulation test and mucus: shown when trying to conceive,
  /// or when the day already has any of them.
  final bool fertility;

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  late CycleDayLog _log = widget.initial;
  late final _note = TextEditingController(text: widget.initial.note ?? '');
  late final _temperature = TextEditingController(
    text: widget.initial.temperature?.toStringAsFixed(2) ?? '',
  );

  @override
  void dispose() {
    _note.dispose();
    _temperature.dispose();
    super.dispose();
  }

  /// "36.6", "36,6" or «۳۶٫۶» — whatever the keyboard gave. Null when
  /// empty, or outside what a thermometer in a mouth can read.
  double? get _parsedTemperature {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    var text = _temperature.text.trim();
    for (var i = 0; i < 10; i++) {
      text = text.replaceAll(persian[i], '$i').replaceAll(arabic[i], '$i');
    }
    text = text.replaceAll('٫', '.').replaceAll(',', '.');
    final value = double.tryParse(text);
    return value == null || value < 34 || value > 43 ? null : value;
  }

  CyclePeriod? get _period {
    final date = CycleDate.of(widget.day);
    for (final p in widget.periods.reversed) {
      if (p.contains(date)) return p;
    }
    return null;
  }

  Future<void> _save() async {
    await widget.services.cycleSaveDay(
      _log.copyWith(
        note: () => _note.text,
        temperature: () => _parsedTemperature,
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _startHere() async {
    await widget.services.cycleStartPeriod(widget.day);
    // A day that starts a period bled; say so unless something else was
    // already chosen.
    if (_log.flow == null) {
      _log = _log.copyWith(flow: () => CycleFlow.medium);
    }
    await _save();
  }

  Future<void> _endHere(CyclePeriod period) async {
    await widget.services.cycleEndPeriod(period.id, widget.day);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rose = cyclePeriodColor(theme.brightness);
    final period = _period;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: NexSpacing.md, bottom: NexSpacing.xs),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return NexSheetBody(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              cycleDayMonth(
                context,
                widget.day,
                solar: widget.services.solarCalendar,
              ),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.sm),
            if (period == null)
              OutlinedButton.icon(
                key: const ValueKey('cycle-start-here'),
                onPressed: _startHere,
                icon: Icon(Icons.water_drop_outlined, color: rose),
                label: Text(l10n.cycleStartHere),
              )
            else if (period.isOpen)
              OutlinedButton.icon(
                key: const ValueKey('cycle-end-here'),
                onPressed: () => _endHere(period),
                icon: Icon(Icons.check_circle_outline, color: rose),
                label: Text(l10n.cycleEndHere),
              ),
            heading(l10n.cycleFlow),
            Wrap(
              spacing: NexSpacing.sm,
              runSpacing: NexSpacing.xs,
              children: [
                for (final flow in <CycleFlow?>[null, ...CycleFlow.values])
                  ChoiceChip(
                    label: Text(cycleFlowLabel(l10n, flow)),
                    selected: _log.flow == flow,
                    selectedColor: flow == null
                        ? null
                        : rose.withValues(alpha: 0.25),
                    onSelected: (_) =>
                        setState(() => _log = _log.copyWith(flow: () => flow)),
                  ),
              ],
            ),
            heading(l10n.cycleMood),
            Wrap(
              spacing: NexSpacing.sm,
              runSpacing: NexSpacing.xs,
              children: [
                for (final mood in CycleMood.values)
                  ChoiceChip(
                    avatar: Icon(cycleMoodIcon(mood), size: 18),
                    label: Text(cycleMoodLabel(l10n, mood)),
                    selected: _log.mood == mood,
                    onSelected: (on) => setState(
                      () => _log = _log.copyWith(mood: () => on ? mood : null),
                    ),
                  ),
              ],
            ),
            heading(l10n.cycleEnergy),
            Wrap(
              spacing: NexSpacing.sm,
              children: [
                for (var level = 1; level <= 5; level++)
                  ChoiceChip(
                    label: Text(cycleDigits(context, level)),
                    selected: _log.energy == level,
                    onSelected: (on) => setState(
                      () =>
                          _log = _log.copyWith(energy: () => on ? level : null),
                    ),
                  ),
              ],
            ),
            heading(l10n.cycleSymptoms),
            Wrap(
              spacing: NexSpacing.sm,
              runSpacing: NexSpacing.xs,
              children: [
                for (final symptom in CycleSymptom.values)
                  FilterChip(
                    label: Text(cycleSymptomLabel(l10n, symptom)),
                    selected: _log.symptoms.contains(symptom),
                    onSelected: (on) => setState(
                      () => _log = _log.copyWith(
                        symptoms: on
                            ? {..._log.symptoms, symptom}
                            : ({..._log.symptoms}..remove(symptom)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NexSpacing.md),
            Wrap(
              spacing: NexSpacing.sm,
              runSpacing: NexSpacing.xs,
              children: [
                FilterChip(
                  avatar: const Icon(Icons.medication_outlined, size: 18),
                  label: Text(l10n.cyclePainRelief),
                  selected: _log.painRelief,
                  onSelected: (on) =>
                      setState(() => _log = _log.copyWith(painRelief: on)),
                ),
                FilterChip(
                  avatar: const Icon(Icons.favorite_border, size: 18),
                  label: Text(l10n.cycleIntimacy),
                  selected: _log.intimacy,
                  onSelected: (on) =>
                      setState(() => _log = _log.copyWith(intimacy: on)),
                ),
                FilterChip(
                  avatar: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(l10n.cyclePillTaken),
                  selected: _log.pill,
                  onSelected: (on) =>
                      setState(() => _log = _log.copyWith(pill: on)),
                ),
              ],
            ),
            if (widget.fertility) ...[
              heading(l10n.cycleFertilitySigns),
              TextField(
                key: const ValueKey('cycle-temperature'),
                controller: _temperature,
                // A number: left to right in either language.
                textDirection: TextDirection.ltr,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.cycleTemperature,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: NexSpacing.sm),
              Text(l10n.cycleOvulationTest, style: theme.textTheme.bodyMedium),
              Wrap(
                spacing: NexSpacing.sm,
                children: [
                  for (final test in CycleOvulationTest.values)
                    ChoiceChip(
                      label: Text(
                        test == CycleOvulationTest.positive
                            ? l10n.cycleTestPositive
                            : l10n.cycleTestNegative,
                      ),
                      selected: _log.ovulationTest == test,
                      onSelected: (on) => setState(
                        () => _log = _log.copyWith(
                          ovulationTest: () => on ? test : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: NexSpacing.sm),
              Text(l10n.cycleMucus, style: theme.textTheme.bodyMedium),
              Wrap(
                spacing: NexSpacing.sm,
                runSpacing: NexSpacing.xs,
                children: [
                  for (final mucus in CycleMucus.values)
                    ChoiceChip(
                      label: Text(cycleMucusLabel(l10n, mucus)),
                      selected: _log.mucus == mucus,
                      onSelected: (on) => setState(
                        () => _log = _log.copyWith(
                          mucus: () => on ? mucus : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            heading(l10n.cycleNote),
            NexTextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: NexSpacing.md),
            FilledButton(
              key: const ValueKey('cycle-day-save'),
              onPressed: _save,
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}
