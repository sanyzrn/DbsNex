import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'money.dart';
import 'irr_unit.dart';
import 'strings.dart';
import 'legacy_amount_entry.dart';
import 'privacy.dart';
import 'choices.dart';

/// The pieces the Price Lens's editors and screens share: pills, the
/// money field with its currency picker and rial/toman choice, the
/// discard guard, date labels.

/// Which unit an IRR amount is entered in.
export 'irr_unit.dart';

/// The price field with its currency row and IRR unit choice. The
/// error text appears as soon as the input stops being money.
class PriceLensMoneyField extends StatefulWidget {
  const PriceLensMoneyField({
    super.key,
    required this.controller,
    required this.label,
    required this.currency,
    required this.irrUnit,
    required this.onCurrencyChanged,
    required this.onIrrUnitChanged,
    this.legacyMinor,
    this.error,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final PriceCurrency currency;
  final IrrUnit irrUnit;
  final ValueChanged<PriceCurrency> onCurrencyChanged;
  final ValueChanged<IrrUnit> onIrrUnitChanged;
  final int? legacyMinor;
  final String? error;
  final VoidCallback? onChanged;

  @override
  State<PriceLensMoneyField> createState() => _PriceLensMoneyFieldState();
}

class _PriceLensMoneyFieldState extends State<PriceLensMoneyField> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = priceLensStrings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lensAmountsHidden(context))
          const Text('••••')
        else
          LensAmountEntry(
            legacyMinor: widget.legacyMinor,
            controller: widget.controller,
            currency: widget.currency.code,
            digits: widget.currency.code == 'IRR'
                ? 0
                : widget.currency.exponent,
            unit: widget.irrUnit,
            label: widget.label,
            errorText: widget.error,
          ),
        const SizedBox(height: NexSpacing.sm),
        _CurrencyRow(
          currency: widget.currency,
          onChanged: widget.onCurrencyChanged,
        ),
        if (widget.currency.code == 'IRR') ...[
          const SizedBox(height: NexSpacing.xs),
          LensChoices<IrrUnit>(
            key: const ValueKey('lens-irr-unit'),
            values: IrrUnit.values,
            value: widget.irrUnit,
            label: (unit) =>
                s(context, unit == IrrUnit.rial ? 'rialUnit' : 'tomanUnit'),
            onChanged: widget.onIrrUnitChanged,
          ),
          Text(
            s(context, 'tomanHint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({required this.currency, required this.onChanged});

  final PriceCurrency currency;
  final ValueChanged<PriceCurrency> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('lens-currency'),
      onTap: () => unawaited(
        nexShowSheet<PriceCurrency>(
          context: context,
          builder: (sheetContext) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsetsDirectional.fromSTEB(
              NexSpacing.md,
              NexSpacing.md,
              NexSpacing.md,
              NexSpacing.md,
            ),
            children: [
              Text(
                priceLensStrings(sheetContext, 'currencyLabel'),
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: NexSpacing.sm),
              for (final code in priceCurrencies)
                ListTile(
                  title: Text(
                    code.code,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    priceLensStrings(sheetContext, 'currency${code.code}'),
                  ),
                  trailing: code.code == currency.code
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, code),
                ),
            ],
          ),
        ).then((picked) {
          if (picked != null) onChanged(picked);
        }),
      ),
      borderRadius: BorderRadius.circular(NexRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: priceLensStrings(context, 'currencyLabel'),
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.md,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${currency.code} · ${priceLensStrings(context, 'currency${currency.code}')}',
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
              ),
            ),
            // The way the reading direction goes — the same chevron
            // the other modules flip for Persian.
            Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left
                  : Icons.chevron_right,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks before a sheet with unsaved work closes.
Future<void> confirmPriceLensDiscard(BuildContext context) async {
  final s = priceLensStrings;
  final answer = await nexShowDialog<String>(
    context: context,
    builder: (dialogContext) => NexAlertDialog(
      title: Text(s(dialogContext, 'discardTitle')),
      content: NexDialogBody(child: Text(s(dialogContext, 'discardBody'))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'keep'),
          child: Text(s(dialogContext, 'keepEditing')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'discard'),
          child: Text(s(dialogContext, 'discard')),
        ),
      ],
    ),
  );
  if (answer == 'discard' && context.mounted) Navigator.pop(context);
}

/// "2026/10/13" — "1405/07/20" where the app is set to Jalali — in the
/// locale's own digits, through the shared label.
/// What sits between two facts on one line: «،» in Persian, where a
/// middle dot beside a number reads as the Persian zero («۱ · کیلو» looked
/// like «۱۰») (2.8.4), and « · » in English.
String lensSep(BuildContext context) =>
    NexModuleStrings.persian(context) ? '، ' : ' · ';

String lensFullDate(BuildContext context, DateTime date) =>
    NexModuleStrings.persian(context)
    ? nexReadableDate(date, solar: true, persian: true)
    : nexModuleDateLabel(context, date);
