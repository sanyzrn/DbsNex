part of 'editor.dart';

const _finenessPresets = [999, 916, 875, 750, 705, 585, 375];

extension _EditorFields on _AssetEditorState {
  Widget input(
    TextEditingController controller,
    String label, {
    bool numeric = false,
    bool decimal = false,
    String? errorText,
    String? helperText,
    String? hintText,
    Key? fieldKey,
  }) => NexTextField(
    key: fieldKey,
    controller: controller,
    minLines: 1,
    maxLines: 1,
    keyboardType: numeric
        ? TextInputType.numberWithOptions(decimal: decimal)
        : TextInputType.text,
    maxLength: numeric ? null : 120,
    decoration: InputDecoration(
      labelText: s(label),
      errorText: errorText == null ? null : s(errorText),
      helperText: helperText,
      hintText: hintText,
    ),
  );

  Widget selection<T>(
    T value,
    List<T> options,
    String label,
    String Function(T) text,
    ValueChanged<T> set,
  ) => DropdownButtonFormField<T>(
    key: ValueKey((label, value)),
    initialValue: value,
    isExpanded: true,
    borderRadius: nexDropdownRadius,
    dropdownColor: nexDropdownColor(context),
    decoration: InputDecoration(labelText: s(label)),
    items: [
      for (final option in options)
        DropdownMenuItem(value: option, child: Text(text(option))),
    ],
    onChanged: (v) {
      if (v != null) change(() => set(v));
    },
  );

  Widget dateButton() => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton.icon(
      key: const ValueKey('assets-date'),
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text(
        '${s(isHolding ? 'buyDate' : 'quoteDate')} · '
        '${assetDate(context, date)}',
      ),
      onPressed: () async {
        final today = civilDay(DateTime.now());
        final picked = await nexPickModuleDate(
          context,
          initial: date.isAfter(today) ? today : date,
          first: DateTime(1900),
          last: today,
        );
        if (picked != null && mounted) change(() => date = civilDay(picked));
      },
    ),
  );

  String? karatHelper() {
    final ppt = parseMoney(fineness.text, 0);
    return ppt != null && ppt >= 1 && ppt <= 1000
        ? karatText(context, ppt)
        : null;
  }

  Widget goldWeightLine() {
    final amount = parseMoney(quantity.text, 3);
    final ppt = parseMoney(fineness.text, 0);
    final valid =
        amount != null &&
        amount > 0 &&
        ppt != null &&
        ppt >= 100 &&
        ppt <= 1000;
    final text = valid
        ? s('normalizedGold', {
            'n': fixedNumber(normalizedGoldMg(amount, ppt), 3, fa),
          })
        : s('normalizedHint');
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }

  Widget finenessPresets() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(s('karatPresets'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: NexSpacing.xs),
      Wrap(
        spacing: NexSpacing.sm,
        runSpacing: NexSpacing.xs,
        children: [
          for (final preset in _finenessPresets)
            ChoiceChip(
              key: ValueKey('assets-karat-$preset'),
              label: Text(fixedNumber(BigInt.from(karatOf(preset)), 0, fa)),
              selected: parseMoney(fineness.text, 0) == preset,
              onSelected: (_) {
                fineness.text = '$preset';
                change(() {});
              },
            ),
        ],
      ),
    ],
  );

  Widget goalTargetLine() {
    final target = parseMoney(quantity.text, 3);
    return Text(
      target != null && target > 0
          ? s('targetMithqal', {
              'n': fixedNumber(mesghalMilli(BigInt.from(target)), 3, fa),
            })
          : s('goalWhy'),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  Widget detailsFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(s('moreDetailsHint'), style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: NexSpacing.sm),
      dateButton(),
      if (dateError != null)
        Text(
          s(dateError!),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const SizedBox(height: NexSpacing.sm),
      selection(
        custody,
        Custody.values,
        'custody',
        (c) => s(c.name),
        (v) => custody = v,
      ),
      const SizedBox(height: NexSpacing.md),
      input(
        location,
        custody == Custody.platform ? 'platformName' : 'locationName',
        errorText: locationError,
      ),
    ],
  );

  List<Widget> fields(BuildContext context) {
    if (isGoal) {
      return [
        input(
          name,
          'goalName',
          errorText: nameError,
          fieldKey: const ValueKey('assets-goal-name'),
        ),
        input(
          quantity,
          'target',
          numeric: true,
          decimal: true,
          errorText: quantityError,
          fieldKey: const ValueKey('assets-goal-target'),
        ),
        goalTargetLine(),
      ];
    }

    final current = market;
    return [
      if (isHolding) ...[
        selection(
          type,
          AssetType.values,
          'assetType',
          (t) => s(t.name),
          (v) => type = v,
        ),
        if (type == AssetType.coin)
          selection(coin, coinCodes, 'coinType', s, (v) => coin = v),
        if (type == AssetType.currency)
          CurrencyField(
            value: currency,
            onChanged: (code) => change(() => currency = code),
          ),
        if (current.custom)
          input(
            name,
            'assetName',
            errorText: nameError,
            helperText: s('customNameHint'),
            fieldKey: const ValueKey('assets-name'),
          ),
        input(
          quantity,
          type == AssetType.gold ? 'gramsInput' : 'quantity',
          numeric: true,
          decimal: current.digits > 0,
          errorText: quantityError,
          fieldKey: const ValueKey('assets-quantity'),
        ),
        if (isGold) ...[
          input(
            fineness,
            'fineness',
            numeric: true,
            errorText: finenessError,
            helperText: karatHelper(),
            fieldKey: const ValueKey('assets-fineness'),
          ),
          finenessPresets(),
          goldWeightLine(),
        ],
      ],
      AmountField(
        controller: cost,
        currency: 'IRR',
        digits: 0,
        unit: unit,
        label: s(
          isHolding
              ? isGold
                    ? 'goldCost'
                    : 'costPaid'
              : 'quoteValue',
        ),
        errorText: costError == null ? null : s(costError!),
        fieldKey: const ValueKey('assets-cost'),
      ),
      if (isHolding && isGold)
        Text(s('goldCostHint'), style: Theme.of(context).textTheme.bodySmall),
      if (!isHolding) ...[
        dateButton(),
        if (dateError != null)
          Text(
            s(dateError!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (sameDayQuote != null)
          Text(s('priceSameDay'), style: Theme.of(context).textTheme.bodySmall),
      ],
      if (isHolding)
        NexMoreDetails(
          open: detailsOpen,
          onChanged: (open) => change(() => detailsOpen = open),
          title: s('moreDetails'),
          hint:
              '${s('buyDate')}: ${assetDate(context, date)} · '
              '${s(custody.name)}',
          toggleKey: const ValueKey('assets-more-details'),
          child: detailsFields(),
        ),
    ];
  }
}
