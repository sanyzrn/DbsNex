import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'strings.dart';
import 'widgets.dart';

class ChequeEditorOptions extends StatelessWidget {
  const ChequeEditorOptions({
    super.key,
    required this.fields,
    required this.open,
    required this.remind,
    required this.days,
    required this.minutes,
    required this.sayadState,
    required this.change,
  });
  final Map<String, TextEditingController> fields;
  final bool open, remind;
  final Set<int> days;
  final int minutes;
  final String sayadState;
  final void Function(String, Object) change;
  @override
  Widget build(BuildContext context) {
    final s = chequeStrings;
    return NexMoreDetails(
      open: open,
      onChanged: (v) => change('details', v),
      title: s(context, 'details'),
      hint: s(context, 'detailsHint'),
      toggleKey: const ValueKey('cheque-details'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final key in ['bank', 'account', 'number', 'sayad', 'note'])
            Padding(
              padding: const EdgeInsets.only(bottom: NexSpacing.md),
              child: NexTextField(
                key: ValueKey('cheque-$key'),
                controller: fields[key]!,
                minLines: 1,
                maxLines: key == 'note' ? 4 : 1,
                maxLength: key == 'note'
                    ? 2000
                    : key == 'sayad'
                    ? 16
                    : key == 'number'
                    ? 60
                    : 100,
                decoration: InputDecoration(
                  labelText: s(context, key),
                  counterText: '',
                ),
              ),
            ),
          Text(
            s(context, 'sayadState'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          ChequeChoices(
            values: const ['unknown', 'todo', 'checked'],
            value: sayadState,
            prefix: 'sayad_',
            onChanged: (v) => change('sayadState', v),
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            s(context, 'sayadNotice'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: NexSpacing.md),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: remind,
            onChanged: (v) => change('remind', v),
            title: Text(s(context, 'remind')),
          ),
          if (remind) ...[
            Wrap(
              spacing: NexSpacing.sm,
              runSpacing: NexSpacing.sm,
              children: [
                for (final d in [3, 7, 14, 30, 0])
                  FilterChip(
                    label: Text(
                      s(context, d == 0 ? 'remindOnDay' : 'remindDays', {
                        'n': d,
                      }),
                    ),
                    selected: days.contains(d),
                    onSelected: (selected) => change(
                      'reminderDays',
                      selected ? {...days, d} : ({...days}..remove(d)),
                    ),
                  ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(
                  s(context, 'remindTime', {
                    'time': TimeOfDay(
                      hour: minutes ~/ 60,
                      minute: minutes % 60,
                    ).format(context),
                  }),
                ),
                onPressed: () async {
                  final time = await nexPickModuleTime(
                    context,
                    initial: TimeOfDay(
                      hour: minutes ~/ 60,
                      minute: minutes % 60,
                    ),
                  );
                  if (time != null && context.mounted) {
                    change('minutes', time.hour * 60 + time.minute);
                  }
                },
              ),
            ),
            Text(
              s(context, 'remindHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
