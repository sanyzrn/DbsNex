import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'module.dart';
import 'money_format.dart';
import 'money_input.dart';
import 'money_words.dart';
import 'number_input.dart';

/// The amount field, the way people actually check a number: grouped while
/// typing, and **said in words** underneath — «۵۰٬۰۰۰ تومان» and
/// «پنجاه هزار تومان». A dropped or doubled zero is the most common mistake
/// with money, and the words make it obvious before Save.
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.currency,
    required this.digits,
    required this.unit,
    required this.label,
    this.hint,
    this.errorText,
    this.enabled = true,
    this.fieldKey,
    this.wordsKey,
  });

  final TextEditingController controller;
  final String currency;
  final int digits;
  final IrrUnit unit;
  final String label;
  final String? hint;
  final String? errorText;
  final bool enabled;
  final Key? fieldKey;
  final Key? wordsKey;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  bool _persian = false;
  bool _grouping = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _persian = NexModuleStrings.persian(context);
    // Not only what is typed: a draft, an edited record and the unit switch
    // all put a number in this controller, and every one of them has to read
    // in the script of the page.
    _group();
  }

  @override
  void didUpdateWidget(AmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    // Grouping rewrites the controller, which calls this again; the flag is
    // what stops that from going round.
    if (_grouping) return;
    _grouping = true;
    _group();
    _grouping = false;
    // The words follow the field; they are rebuilt from the same text the
    // parser reads, never from a second copy of the number.
    if (mounted) setState(() {});
  }

  /// Groups as the person types and puts the caret back where it was.
  void _group() {
    final value = widget.controller.value;
    final decimals = amountDisplayDigits(
      widget.currency,
      widget.digits,
      widget.unit,
    );
    // Preserve invalid pasted signs and precision so validation can reject
    // them. Dropping a decimal separator could otherwise multiply a price.
    final normalized = normalizeNumber(value.text).replaceAll('٫', '.');
    final parts = normalized.split('.');
    if (!RegExp(r'^[0-9,٬.]*$').hasMatch(normalized) ||
        parts.length > 2 ||
        (parts.length == 2 &&
            (decimals == 0 ||
                parts.last.length > decimals ||
                !RegExp(r'^[0-9]*$').hasMatch(parts.last)))) {
      return;
    }
    final grouped = groupAmountEdit(
      value.text,
      value.selection.baseOffset < 0
          ? value.text.length
          : value.selection.baseOffset,
      decimals,
      persian: _persian,
    );
    if (grouped.text == value.text &&
        grouped.caret == value.selection.baseOffset) {
      return;
    }
    widget.controller.value = TextEditingValue(
      text: grouped.text,
      selection: TextSelection.collapsed(offset: grouped.caret),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = assetStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final parsed = parseAmount(
      widget.controller.text,
      widget.currency,
      widget.digits,
      widget.unit,
    );
    final unitWord = currencyUnitWord(
      widget.currency,
      widget.unit,
      persian: persian,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: widget.fieldKey,
          controller: widget.controller,
          enabled: widget.enabled,
          keyboardType: TextInputType.numberWithOptions(
            decimal:
                amountDisplayDigits(
                  widget.currency,
                  widget.digits,
                  widget.unit,
                ) >
                0,
          ),
          // Digits run left to right in both languages; in Persian the
          // field starts at the right, beside the word for the unit.
          textDirection: persian ? TextDirection.rtl : TextDirection.ltr,
          textAlign: TextAlign.start,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            errorText: widget.errorText,
            suffixText: unitWord,
          ),
        ),
        if (parsed != null && parsed > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: NexSpacing.xs,
              top: NexSpacing.xs,
            ),
            child: Text(
              formatAmountWords(
                parsed,
                widget.currency,
                widget.digits,
                persian,
                widget.unit,
              ),
              key: widget.wordsKey,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else if (!widget.enabled)
          const SizedBox.shrink()
        else
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: NexSpacing.xs,
              top: NexSpacing.xs,
            ),
            child: Text(
              strings(context, 'amountWordsHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
