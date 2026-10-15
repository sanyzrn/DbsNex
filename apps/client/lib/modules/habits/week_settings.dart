import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';

/// Module-local preference; never inferred from the presentation language.
int readFirstDay(Map<String, Object?>? body) {
  final value = body?['firstDay'];
  return value is int && value >= 1 && value <= 7 ? value : DateTime.saturday;
}

Future<void> showWeekSettings(
  BuildContext context,
  NexModuleStore store,
  int firstDay,
) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) => _WeekSettings(store: store, firstDay: firstDay),
);

class _WeekSettings extends StatefulWidget {
  const _WeekSettings({required this.store, required this.firstDay});
  final NexModuleStore store;
  final int firstDay;
  @override
  State<_WeekSettings> createState() => _WeekSettingsState();
}

class _WeekSettingsState extends State<_WeekSettings> {
  late int _day = widget.firstDay;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.put('settings', 'week', {'v': 1, 'firstDay': _day});
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = habitsStrings(context, 'saveError'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(NexSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            habitsStrings(context, 'weekStart'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            habitsStrings(context, 'weekStartHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: NexSpacing.md),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              for (final day in const [6, 7, 1, 2, 3, 4, 5])
                ChoiceChip(
                  key: ValueKey('habit-week-start-$day'),
                  label: Text(habitsStrings(context, 'weekday$day')),
                  selected: _day == day,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _day = day),
                ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: NexSpacing.lg),
          FilledButton(
            key: const ValueKey('habit-week-save'),
            onPressed: _saving ? null : _save,
            child: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
    ),
  );
}
