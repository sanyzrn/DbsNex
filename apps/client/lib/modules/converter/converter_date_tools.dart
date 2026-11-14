import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'converter_date.dart';
import 'converter_format.dart';
import 'converter_number.dart';
import 'converter_strings.dart';
import 'converter_widgets.dart';

/// The two date sums, each in its own sheet so the Dates tab stays one date
/// and one answer.
Future<void> converterShowDaysBetween(
  BuildContext context, {
  required ConverterCalendar calendar,
  required ConverterDate initial,
}) => nexShowSheet<void>(
  context: context,
  builder: (_) => _DaysBetweenSheet(calendar: calendar, initial: initial),
);

Future<void> converterShowAddDays(
  BuildContext context, {
  required ConverterCalendar calendar,
  required ConverterDate initial,
}) => nexShowSheet<void>(
  context: context,
  builder: (_) => _AddDaysSheet(calendar: calendar, initial: initial),
);

/// The padding both sheets share: their margin, and room for the keyboard
/// when a field has focus.
EdgeInsetsGeometry _sheetPadding(BuildContext context) =>
    EdgeInsetsDirectional.only(
      start: NexSpacing.md,
      end: NexSpacing.md,
      top: NexSpacing.md,
      bottom:
          NexSpacing.md +
          MediaQuery.viewInsetsOf(context).bottom +
          nexBottomInset(context),
    );

Widget _sheetTitle(BuildContext context, String text) => Padding(
  padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.md),
  child: Text(text, style: Theme.of(context).textTheme.titleLarge),
);

Widget _closeButton(BuildContext context) => Align(
  alignment: AlignmentDirectional.centerEnd,
  child: TextButton(
    key: const ValueKey('converter-sheet-close'),
    onPressed: () => Navigator.of(context).pop(),
    child: Text(converterText(context, 'close')),
  ),
);

/// Picking a day with the app's own picker, then writing it back into the
/// field in the calendar the sheet is working in.
Future<void> _pick(
  BuildContext context, {
  required ConverterCalendar calendar,
  required TextEditingController controller,
  required VoidCallback onChanged,
}) async {
  final current = ConverterDate.parse(controller.text, calendar);
  final picked = await nexPickModuleDate(
    context,
    initial: current?.civilDay ?? DateTime.now(),
    first: DateTime(converterFirstCivilYear),
    last: DateTime(converterLastCivilYear, 12, 31),
  );
  if (picked == null || !context.mounted) return;
  final converted = ConverterDate.of(picked, calendar);
  if (converted == null) return;
  controller.text = converterDateNumeric(context, converted);
  onChanged();
}

class _DaysBetweenSheet extends StatefulWidget {
  const _DaysBetweenSheet({required this.calendar, required this.initial});

  final ConverterCalendar calendar;
  final ConverterDate initial;

  @override
  State<_DaysBetweenSheet> createState() => _DaysBetweenSheetState();
}

class _DaysBetweenSheetState extends State<_DaysBetweenSheet> {
  late final TextEditingController _from;
  late final TextEditingController _to;

  @override
  void initState() {
    super.initState();
    _from = TextEditingController();
    _to = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_from.text.isEmpty) {
      _from.text = converterDateNumeric(context, widget.initial);
    }
    if (_to.text.isEmpty) {
      _to.text = converterDateNumeric(context, widget.initial);
    }
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final strings = converterStrings;
    final theme = Theme.of(context);
    final first = ConverterDate.parse(_from.text, widget.calendar);
    final second = ConverterDate.parse(_to.text, widget.calendar);
    final days = first == null || second == null
        ? null
        : first.daysUntil(second);
    final result = switch (days) {
      null => '—',
      0 => strings(context, 'daysSameDay'),
      final count when count > 0 => strings(context, 'daysBetweenResult', {
        'n': count,
      }),
      final count => strings(context, 'daysEarlier', {'n': -count}),
    };
    return Padding(
      padding: _sheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTitle(context, strings(context, 'daysBetweenTitle')),
            ConverterDateField(
              fieldKey: const ValueKey('converter-days-from'),
              controller: _from,
              onChanged: (_) => _changed(),
              onPick: () => _pick(
                context,
                calendar: widget.calendar,
                controller: _from,
                onChanged: _changed,
              ),
              errorText: first == null ? strings(context, 'dateInvalid') : null,
            ),
            const SizedBox(height: NexSpacing.sm),
            ConverterDateField(
              fieldKey: const ValueKey('converter-days-to'),
              controller: _to,
              onChanged: (_) => _changed(),
              onPick: () => _pick(
                context,
                calendar: widget.calendar,
                controller: _to,
                onChanged: _changed,
              ),
              errorText: second == null
                  ? strings(context, 'dateInvalid')
                  : null,
            ),
            const SizedBox(height: NexSpacing.lg),
            Text(
              result,
              key: const ValueKey('converter-days-result'),
              style: theme.textTheme.headlineSmall,
            ),
            ConverterNote(text: strings(context, 'daysBetweenNote')),
            const SizedBox(height: NexSpacing.sm),
            _closeButton(context),
          ],
        ),
      ),
    );
  }
}

class _AddDaysSheet extends StatefulWidget {
  const _AddDaysSheet({required this.calendar, required this.initial});

  final ConverterCalendar calendar;
  final ConverterDate initial;

  @override
  State<_AddDaysSheet> createState() => _AddDaysSheetState();
}

class _AddDaysSheetState extends State<_AddDaysSheet> {
  late final TextEditingController _start;
  late final TextEditingController _count;

  @override
  void initState() {
    super.initState();
    _start = TextEditingController();
    _count = TextEditingController(text: '7');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_start.text.isEmpty) {
      _start.text = converterDateNumeric(context, widget.initial);
    }
  }

  @override
  void dispose() {
    _start.dispose();
    _count.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final strings = converterStrings;
    final theme = Theme.of(context);
    final start = ConverterDate.parse(_start.text, widget.calendar);
    final count = converterParseNumber(_count.text);
    final whole = count == null || count != count.roundToDouble()
        ? null
        : count.toInt();
    final result = start == null || whole == null ? null : start.addDays(whole);
    return Padding(
      padding: _sheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTitle(context, strings(context, 'addDaysTitle')),
            ConverterDateField(
              fieldKey: const ValueKey('converter-add-start'),
              controller: _start,
              onChanged: (_) => _changed(),
              onPick: () => _pick(
                context,
                calendar: widget.calendar,
                controller: _start,
                onChanged: _changed,
              ),
              errorText: start == null && _start.text.trim().isNotEmpty
                  ? strings(context, 'dateInvalid')
                  : null,
            ),
            const SizedBox(height: NexSpacing.sm),
            TextField(
              key: const ValueKey('converter-days-count'),
              controller: _count,
              onChanged: (_) => _changed(),
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: strings(context, 'addDaysCount'),
                errorText: whole == null
                    ? strings(context, 'daysInvalid')
                    : null,
              ),
            ),
            const SizedBox(height: NexSpacing.lg),
            if (result == null)
              Text('—', style: theme.textTheme.headlineSmall)
            else ...[
              Text(
                strings(context, 'addDaysResult'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                converterDateLabel(context, result),
                key: const ValueKey('converter-add-days-result'),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: NexSpacing.xs),
              Text(
                result.civilDay == null
                    ? ''
                    : converterWeekdayName(context, result.civilDay!),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: NexSpacing.md),
              for (final calendar in ConverterCalendar.values)
                if (result.inCalendar(calendar) case final other?)
                  ConverterInfoRow(
                    label: converterCalendarName(context, calendar),
                    value: converterDateLabel(context, other),
                  ),
            ],
            ConverterNote(text: strings(context, 'addDaysNote')),
            const SizedBox(height: NexSpacing.sm),
            _closeButton(context),
          ],
        ),
      ),
    );
  }
}
