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
import 'storage_money.dart';
import 'units.dart';
import 'local_values.dart';
import 'draft_guard.dart';
import 'legacy_amount_entry.dart';
import 'privacy.dart';

part 'option_editor_actions.dart';
part 'editor_draft.dart';
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
  NexModuleStore? store,
  Future<void> Function(PriceOption)? persist,
  bool priceEntry = false,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: lensRouteBuilder(
    context,
    OptionEditorSheet(
      existing: existing,
      onSave: onSave,
      store: store,
      persist: persist,
      priceEntry: priceEntry,
    ),
  ),
);

class OptionEditorSheet extends StatefulWidget {
  const OptionEditorSheet({
    super.key,
    required this.onSave,
    this.existing,
    this.store,
    this.persist,
    this.priceEntry = false,
  });
  final NexModuleStore? store;
  final Future<void> Function(PriceOption)? persist;
  final bool priceEntry;

  final PriceOption? existing;
  final ValueChanged<PriceOption> onSave;

  @override
  State<OptionEditorSheet> createState() => _OptionEditorSheetState();
}

class _OptionEditorSheetState extends State<OptionEditorSheet> {
  late final TextEditingController _label = TextEditingController(
    text: widget.existing?.label ?? '',
  );
  late final _price = lensMoneyController(
    widget.priceEntry ? '' : initialPriceText(widget.existing),
    widget.existing,
    widget.priceEntry ? null : widget.existing?.priceMinor,
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
  late final _discount = lensMoneyController(
    initialDiscountText(widget.existing, _currency.exponent),
    widget.existing,
    widget.existing?.discountMinor,
  );
  late final _shipping = lensMoneyController(
    initialShippingText(widget.existing, _currency.exponent),
    widget.existing,
    widget.existing?.shippingMinor,
  );

  late final _product = TextEditingController(
    text: widget.existing?.productName ?? '',
  );
  late final _shop = TextEditingController(
    text: widget.priceEntry ? '' : widget.existing?.shop ?? '',
  );
  late bool _details = widget.existing != null && !widget.priceEntry;

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

  late String _id = widget.priceEntry
      ? widget.store!.newId()
      : widget.existing?.id ??
            widget.store?.newId() ??
            'opt-${DateTime.now().microsecondsSinceEpoch}';
  bool _dateConfirmed = true;
  bool _unitConfirmed = true, _currencyConfirmed = true;
  bool _saving = false, _initializing = true, _refreshPending = false;
  bool _loading = false, _loadFailed = false;
  PriceOption? _committed;
  Map<String, TextEditingController> get _controllers => {
    'label': _label,
    'price': _price,
    'quantity': _quantity,
    'count': _count,
    'paid': _paidCount,
    'discount': _discount,
    'shipping': _shipping,
    'date': _dateText,
    'productName': _product,
    'shop': _shop,
  };
  late final NexModuleFormDraft? _draft = widget.store == null
      ? null
      : NexModuleFormDraft(
          widget.store!,
          'offer:${widget.priceEntry ? 'price-${widget.existing?.productLabel ?? 'new'}' : widget.existing?.id ?? 'new'}',
          widget.priceEntry
              ? {'entry': 'price'}
              : widget.existing?.toBody() ?? {},
          _controllers,
          () => {
            'recordId': _id,
            'currency': _currency.code,
            'unit': _unitKey,
            'irrUnit': _irrUnit.name,
            'discountKind': _discountKind.name,
            'details': _details,
          },
        );

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
    for (final c in _controllers.values) {
      c.addListener(_markDirty);
    }
    unawaited(_loadDraft());
  }

  void _paint(VoidCallback action) {
    if (mounted) setState(action);
  }

  @override
  void dispose() {
    _draft?.close();
    for (final c in _controllers.values) {
      c.removeListener(_markDirty);
    }
    _product.dispose();
    _shop.dispose();
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

  void _markDirty() {
    if (_initializing) return;
    _dirty = true;
    _draft?.changed();
    if (WidgetsBinding.instance.schedulerPhase.name != 'persistentCallbacks') {
      if (mounted) setState(() {});
      return;
    }
    if (_refreshPending) return;
    _refreshPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPending = false;
      if (mounted) setState(() {});
    });
  }

  PriceAmountResult get _parsedPrice => parseMoneyIn(
    _price.text,
    _currency,
    _irrUnit,
    legacyMinor: widget.priceEntry ? null : widget.existing?.priceMinor,
  );

  Fraction? get _parsedQuantity => fractionFromDecimal(_quantity.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = priceLensStrings;
    final body = PopScope(
      canPop: _draft != null || !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (_draft == null && !didPop && !_saving) {
          unawaited(confirmPriceLensDiscard(context));
        }
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
                      : widget.priceEntry
                      ? 'newPrice'
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
                  children: _loading
                      ? [const LinearProgressIndicator()]
                      : _loadFailed
                      ? [
                          Text(s(context, 'loadFailed')),
                          TextButton(
                            onPressed: _loadDraft,
                            child: Text(s(context, 'retry')),
                          ),
                        ]
                      : [
                          AbsorbPointer(
                            absorbing: _saving || _committed != null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: editorFields(context),
                            ),
                          ),
                        ],
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
              onPressed: _saving || _loading || _loadFailed
                  ? null
                  : () => unawaited(_save()),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(s(context, _committed == null ? 'save' : 'retry')),
            ),
          ],
        ),
      ),
    );
    return _draft == null
        ? body
        : DraftGuard(
            draft: _draft,
            busy: () => _saving || _loading,
            child: body,
          );
  }
}
