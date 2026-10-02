import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import '../platform/vault_store.dart' show vaultLatinDigits;
import 'feature_label.dart';

class RecurringOptions extends StatelessWidget {
  const RecurringOptions({
    super.key,
    required this.cadence,
    required this.value,
    required this.onChanged,
  });
  final NexCadence cadence;
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  @override
  Widget build(BuildContext context) {
    void set(String key, dynamic v) => onChanged({...value, key: v});
    final weekdays = (value['weekdays'] as List? ?? const []).cast<int>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cadence == NexCadence.weeks) ...[
          Text(
            nexLabel(
              context,
              'Days of the week (optional)',
              'روزهای هفته (اختیاری)',
            ),
          ),
          Wrap(
            spacing: 4,
            children: [
              // Saturday first in Persian, where the week starts on شنبه, as
              // the recurring calendar already does (LOC-11). The stored
              // values stay DateTime.weekday numbers either way.
              for (final i
                  in Localizations.localeOf(context).languageCode == 'fa'
                      ? const [6, 7, 1, 2, 3, 4, 5]
                      : const [1, 2, 3, 4, 5, 6, 7])
                FilterChip(
                  label: Text(
                    nexLabel(
                      context,
                      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i - 1],
                      [
                        'دوشنبه',
                        'سه‌شنبه',
                        'چهارشنبه',
                        'پنجشنبه',
                        'جمعه',
                        'شنبه',
                        'یکشنبه',
                      ][i - 1],
                    ),
                  ),
                  selected: weekdays.contains(i),
                  onSelected: (yes) => set(
                    'weekdays',
                    [
                      for (final d in weekdays)
                        if (d != i) d,
                      if (yes) i,
                    ]..sort(),
                  ),
                ),
            ],
          ),
        ],
        if (cadence == NexCadence.months || cadence == NexCadence.years) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              nexLabel(
                context,
                'Repeat by Persian calendar',
                'تکرار بر اساس تقویم شمسی',
              ),
            ),
            subtitle: Text(
              nexLabel(
                context,
                'Controls the schedule, not just the displayed date',
                'محاسبهٔ موعدها با ماه و سال شمسی',
              ),
            ),
            value: value['solar'] == true,
            onChanged: (v) => set('solar', v),
          ),
          // Room for the field's floating label, which otherwise sat on the
          // row above it.
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: value['monthDay'] as int? ?? -1,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              labelText: nexLabel(context, 'Day of month', 'روز ماه'),
            ),
            items: [
              DropdownMenuItem(
                value: -1,
                child: Text(
                  nexLabel(
                    context,
                    'From the first due date',
                    'مطابق موعد اول',
                  ),
                ),
              ),
              DropdownMenuItem(
                value: 0,
                child: Text(nexLabel(context, 'Last day', 'آخر ماه')),
              ),
              for (var d = 1; d <= 31; d++)
                DropdownMenuItem(
                  value: d,
                  child: Text(
                    nexDigits(
                      '$d',
                      persian:
                          Localizations.localeOf(context).languageCode == 'fa',
                    ),
                  ),
                ),
            ],
            onChanged: (v) => set('monthDay', v == -1 ? null : v),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          initialValue: value['amountMinor'] == null
              ? ''
              : ((value['amountMinor'] as int) / 100).toStringAsFixed(2),
          decoration: InputDecoration(
            labelText: nexLabel(
              context,
              'Amount per occurrence (optional)',
              'مبلغ هر نوبت (اختیاری)',
            ),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          onChanged: (v) {
            final normalized = vaultLatinDigits(v.trim()).replaceAll('٫', '.');
            final valid =
                normalized.isEmpty ||
                RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(normalized);
            onChanged({
              ...value,
              'invalidAmount': !valid,
              'amountMinor': valid && normalized.isNotEmpty
                  ? (double.parse(normalized) * 100).round()
                  : null,
            });
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: value['currency'] as String? ?? 'IRT',
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            labelText: nexLabel(
              context,
              'Currency (totals stay separate)',
              'واحد پول (جمع هر ارز جداست)',
            ),
          ),
          items: [
            for (final c in ['IRT', 'IRR', 'USD', 'EUR', 'GBP', 'CAD', 'AED'])
              DropdownMenuItem(
                value: c,
                child: Text(
                  c == 'IRT'
                      ? nexLabel(context, 'Toman', 'تومان')
                      : c == 'IRR'
                      ? nexLabel(context, 'Rial', 'ریال')
                      : c,
                ),
              ),
          ],
          onChanged: (v) => set('currency', v),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
