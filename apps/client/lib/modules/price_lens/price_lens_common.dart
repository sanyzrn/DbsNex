import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'money.dart';
import 'strings.dart';

/// The pieces the Price Lens's editors and screens share: pills, the
/// money field with its currency picker and rial/toman choice, the
/// discard guard, date labels.

/// Which unit an IRR amount is entered in.
enum IrrUnit { rial, toman }

/// A calm pill that always meets the 48dp floor — the module's own
/// selection control, wrapping where a segmented row would overflow.
class LensPill extends StatelessWidget {
  const LensPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return IntrinsicWidth(
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(NexRadius.pill),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: NexSpacing.md,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    this.error,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final PriceCurrency currency;
  final IrrUnit irrUnit;
  final ValueChanged<PriceCurrency> onCurrencyChanged;
  final ValueChanged<IrrUnit> onIrrUnitChanged;
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
        TextField(
          controller: widget.controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: widget.label,
            suffixText: widget.currency.code,
            errorText: widget.error,
          ),
          onChanged: (text) {
            setState(() {}); // the error follows the typing
            widget.onChanged?.call();
          },
        ),
        const SizedBox(height: NexSpacing.sm),
        _CurrencyRow(
          currency: widget.currency,
          onChanged: widget.onCurrencyChanged,
        ),
        if (widget.currency.code == 'IRR') ...[
          const SizedBox(height: NexSpacing.xs),
          Wrap(
            key: const ValueKey('lens-irr-unit'),
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              for (final unit in IrrUnit.values)
                LensPill(
                  label: s(
                    context,
                    unit == IrrUnit.rial ? 'rialUnit' : 'tomanUnit',
                  ),
                  selected: unit == widget.irrUnit,
                  onTap: () => widget.onIrrUnitChanged(unit),
                ),
            ],
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
            const Icon(Icons.chevron_right, size: 20),
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

/// "13 October 2026" for pickers and info lines.
String lensFullDate(BuildContext context, DateTime date) =>
    nexModuleDateLabel(context, date);
