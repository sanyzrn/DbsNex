part of 'editor.dart';

extension _EditorFields on _AssetEditorState {
  Widget input(
    TextEditingController controller,
    String label, {
    bool numeric = false,
    bool decimal = false,
  }) => NexTextField(
    controller: controller,
    minLines: 1,
    maxLines: 1,
    keyboardType: numeric
        ? TextInputType.numberWithOptions(decimal: decimal)
        : TextInputType.text,
    maxLength: numeric ? null : 120,
    decoration: InputDecoration(labelText: s(label)),
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

  List<Widget> fields(BuildContext context) {
    if (isGoal) {
      return [
        input(name, 'goalName'),
        input(quantity, 'target', numeric: true, decimal: true),
        Text(s('goalWhy')),
      ];
    }
    return [
      if (!isHolding)
        Text(
          marketLabel(context, market, forQuote: true),
          style: Theme.of(context).textTheme.titleMedium,
        ),
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
        if (market.custom) input(name, 'assetName'),
        input(
          quantity,
          type == AssetType.gold ? 'gramsInput' : 'quantity',
          numeric: true,
          decimal: market.digits > 0,
        ),
        if (type == AssetType.gold) input(fineness, 'fineness', numeric: true),
      ],
      AmountField(
        controller: cost,
        currency: 'IRR',
        digits: 0,
        unit: unit,
        label: s(
          isHolding
              ? type == AssetType.gold
                    ? 'goldCost'
                    : 'costPaid'
              : 'quoteValue',
        ),
      ),
      TextButton.icon(
        icon: const Icon(Icons.calendar_month_outlined),
        label: Text(
          '${s(isHolding ? 'buyDate' : 'quoteDate')} · ${assetDate(context, date)}',
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
      if (isHolding) ...[
        selection(
          custody,
          Custody.values,
          'custody',
          (c) => s(c.name),
          (v) => custody = v,
        ),
        input(
          location,
          custody == Custody.platform ? 'platformName' : 'locationName',
        ),
      ],
      if (!isHolding && type == AssetType.gold) Text(s('metalHint')),
    ];
  }
}
