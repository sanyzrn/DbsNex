import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'editor_helpers.dart';
import 'money.dart';
import 'options.dart';
import 'option_editor_sections.dart';
import 'price_lens_common.dart';
import 'rational.dart';
import 'strings.dart';
import 'units.dart';
import 'local_values.dart';

part 'option_editor_actions.dart';
part 'option_editor_fields.dart';

/// The offer editor: what it is, the total price with its currency
/// and rial/toman choice, the quantity per package with its unit, the
/// package count (and what was actually paid for, in a buy-N-get-M),
/// one discount applied once, an optional shipping share, and the
/// date. Unsaved work is guarded on the way out.
Future<void> showOptionEditor(
  BuildContext context, {
  required ValueChanged<PriceOption> onSave,
  PriceOption? existing,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) => OptionEditorSheet(existing: existing, onSave: onSave),
);

class OptionEditorSheet extends StatefulWidget {
  const OptionEditorSheet({super.key, required this.onSave, this.existing});

  final PriceOption? existing;
  final ValueChanged<PriceOption> onSave;

  @override
  State<OptionEditorSheet> createState() => _OptionEditorSheetState();
}

class _OptionEditorSheetState extends State<OptionEditorSheet> {
  late final TextEditingController _label = TextEditingController(
    text: widget.existing?.label ?? '',
  );
  late final TextEditingController _price = TextEditingController(
    text: initialPriceText(widget.existing),
  );
  late final TextEditingController _quantity = TextEditingController(
    text: initialQuantityText(widget.existing),
  );
  late final TextEditingController _count = TextEditingController(
    text: '${widget.existing?.packageCount ?? 1}',
  );
  late final TextEditingController _paidCount = TextEditingController(
    text: '${widget.existing?.paidCount ?? ''}',
  );
  late final TextEditingController _discount = TextEditingController(
    text: initialDiscountText(widget.existing, _currency.exponent),
  );
  late final TextEditingController _shipping = TextEditingController(
    text: initialShippingText(widget.existing, _currency.exponent),
  );

  late PriceCurrency _currency = initialCurrencyOf(widget.existing);
  late IrrUnit _irrUnit = IrrUnit.rial;
  late String _unitKey = priceUnitOf(widget.existing?.unitKey)?.key ?? 'kg';
  late DiscountKind _discountKind =
      widget.existing?.discount ?? DiscountKind.none;

  /// The shopping date as typed civil text, `yyyy/MM/dd`, shared Jalali
  /// entry beside it. Empty means undated; the stored body stays ISO 8601.
  late final TextEditingController _dateText = TextEditingController(
    text: _initialDateText,
  );

  late final String _id =
      widget.existing?.id ?? 'opt-${DateTime.now().microsecondsSinceEpoch}';
  bool _dateConfirmed = true;
  bool _unitConfirmed = true, _currencyConfirmed = true;
  bool _saving = false;
  bool _dirty = false;
  bool _showErrors = false;

  PriceUnit get _unit => priceUnitOf(_unitKey)!;

  /// The prefilled date text: the stored day in the shared entry's format.
  String get _initialDateText {
    final date = widget.existing?.date;
    if (date == null) return '';
    return '${date.year}'
        '/${date.month.toString().padLeft(2, '0')}'
        '/${date.day.toString().padLeft(2, '0')}';
  }

  /// The typed date, parsed — null when the text is empty or not a day.
  DateTime? get _parsedDate => LocalValues.day(_dateText.text);

  /// The field's live error: a stored date that no longer parses, a typed
  /// day that is not one, or a day still in the future.
  bool get _dateProblem =>
      !_dateConfirmed ||
      (_dateText.text.trim().isNotEmpty &&
          ((_parsedDate == null) || _parsedDate!.isAfter(DateTime.now())));

  @override
  void initState() {
    super.initState();
    _unitConfirmed = widget.existing == null || widget.existing!.unit != null;
    _currencyConfirmed =
        widget.existing == null ||
        priceCurrencyOf(widget.existing!.currency) != null;
    _dateConfirmed =
        widget.existing == null ||
        widget.existing!.source?['date'] == null ||
        LocalValues.day(_initialDateText) != null;
    // Typing and the shared calendar button both change the controller,
    // so the controller — not onChanged — marks the sheet dirty.
    _dateText.addListener(_markDirty);
  }

  void _paint(VoidCallback action) {
    if (mounted) setState(action);
  }

  @override
  void dispose() {
    _dateText.removeListener(_markDirty);
    _dateText.dispose();
    _label.dispose();
    _price.dispose();
    _quantity.dispose();
    _count.dispose();
    _paidCount.dispose();
    _discount.dispose();
    _shipping.dispose();
    super.dispose();
  }

  void _markDirty() => setState(() => _dirty = true);

  PriceAmountResult get _parsedPrice =>
      parseMoneyIn(_price.text, _currency, _irrUnit);

  Fraction? get _parsedQuantity => fractionFromDecimal(_quantity.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = priceLensStrings;
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) unawaited(confirmPriceLensDiscard(context));
      },
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          NexSpacing.md,
          0,
          NexSpacing.md,
          NexSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                s(
                  context,
                  widget.existing == null
                      ? 'newOptionTitle'
                      : 'editOptionTitle',
                ),
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: editorFields(context),
                ),
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            if (_showErrors)
              Text(
                s(context, 'checkFields'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            FilledButton(
              key: const ValueKey('lens-save'),
              onPressed: _saving ? null : () => unawaited(_save()),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(s(context, 'save')),
            ),
          ],
        ),
      ),
    );
  }
}
