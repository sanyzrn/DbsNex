import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'amount_field.dart';
import 'currency_field.dart';
import 'currency_scales.dart';
import 'draft_guard.dart';
import 'irr_unit.dart';
import 'model.dart';
import 'money_format.dart';
import 'presentation.dart';
import 'strings.dart';
import 'valuation.dart';

part 'editor_fields.dart';

class AssetEditor extends StatefulWidget {
  const AssetEditor({
    super.key,
    required this.store,
    required this.revealed,
    required this.kind,
    required this.initialMarket,
    required this.initialUnit,
    required this.save,
    this.original,
    this.quotes = const [],
  });
  final NexModuleStore store;
  final ValueNotifier<bool> revealed;
  final String kind;
  final AssetMarket initialMarket;
  final IrrUnit initialUnit;
  final ModuleRecord? original;
  final Future<void> Function(String id, Fields body) save;

  /// The book's recorded prices, so the sheet can say when a day already has
  /// one without going back to storage on every keystroke.
  final List<Quote> quotes;

  @override
  State<AssetEditor> createState() => _AssetEditorState();
}

class _AssetEditorState extends State<AssetEditor> {
  final name = TextEditingController(),
      quantity = TextEditingController(),
      cost = TextEditingController(),
      fineness = TextEditingController(text: '750'),
      location = TextEditingController();
  late final holding = Holding.read(widget.original ?? _empty);
  late final quote = Quote.read(widget.original ?? _empty);
  late final goal = AssetGoal.read(widget.original ?? _empty);
  static final _empty = ModuleRecord(
    module: 'assets',
    id: '',
    kind: '',
    body: const {},
    updatedAt: DateTime(2000),
  );

  late AssetType type = widget.initialMarket.type;
  late String coin = widget.initialMarket.type == AssetType.coin
      ? widget.initialMarket.code
      : 'emami';
  late String currency = widget.initialMarket.type == AssetType.currency
      ? widget.initialMarket.code
      : 'USD';
  late Custody custody = holding?.custody ?? Custody.home;
  late DateTime date =
      holding?.bought ?? quote?.date ?? civilDay(DateTime.now());
  late IrrUnit unit = widget.initialUnit;
  late String id = widget.original?.id ?? widget.store.newId();
  bool loading = true,
      failed = false,
      busy = false,
      committed = false,
      detailsOpen = false;
  String? error;
  String? nameError, quantityError, costError, finenessError, locationError;
  String? dateError;
  late final draft = NexModuleFormDraft(
    widget.store,
    '${widget.kind}:${widget.original?.id ?? (widget.kind == 'quote' ? '${widget.initialMarket.key}:new' : 'new')}',
    widget.original?.body ?? const {'v': 1},
    {
      'name': name,
      'quantity': quantity,
      'cost': cost,
      'fineness': fineness,
      'location': location,
    },
    () => {
      'type': type.name,
      'coin': coin,
      'currency': currency,
      'custody': custody.name,
      'date': date.toIso8601String(),
      'unit': unit.key,
      'recordId': id,
      'details': detailsOpen ? '1' : '',
    },
  );

  String s(String key, [Fields args = const {}]) =>
      assetStrings(context, key, args);
  bool get isHolding => widget.kind == 'holding';
  bool get isGoal => widget.kind == 'goal';
  bool get isGold => type == AssetType.gold;
  bool get fa => NexModuleStrings.persian(context);
  AssetMarket get market => AssetMarket(
    type,
    code: switch (type) {
      AssetType.coin => coin,
      AssetType.currency => currency,
      _ => '',
    },
    name: name.text.trim(),
  );

  @override
  void initState() {
    super.initState();
    // Correcting a saved purchase shows everything; a new one asks for the
    // two answers it needs and keeps the rest one button away.
    detailsOpen = holding != null;
    name.text = goal?.title ?? widget.initialMarket.name;
    if (holding case final h?) {
      quantity.text = amountInput(
        h.quantity,
        h.market.type == AssetType.currency ? h.market.code : 'USD',
        h.market.digits,
        unit,
      );
      cost.text = amountInput(h.costPerUnitRial, 'IRR', 0, unit);
      location.text = h.location;
      fineness.text = h.fineness.toString();
    }
    if (quote case final q?) {
      cost.text = amountInput(q.unitRial, 'IRR', 0, unit);
    }
    if (goal case final g?) {
      quantity.text = amountInput(g.targetMg, 'USD', 3, unit);
    }
    unawaited(load());
  }

  Future<void> load() async {
    final data = await draft.load();
    if (!mounted) return;
    if (data != null) {
      draft.apply(data);
      type =
          AssetType.values.where((t) => t.name == data['type']).firstOrNull ??
          type;
      custody =
          Custody.values.where((c) => c.name == data['custody']).firstOrNull ??
          custody;
      if (coinCodes.contains(data['coin'])) coin = data['coin'] as String;
      if (data['currency'] case final String code
          when code != 'IRR' && currencyScales.containsKey(code)) {
        currency = code;
      }
      date = readDay(data['date']) ?? date;
      unit = IrrUnit.fromKey(data['unit']);
      if (data['details'] == '1') detailsOpen = true;
      if (data['recordId'] case final String savedId) {
        if (widget.original == null && savedId.isNotEmpty) id = savedId;
      }
    }
    setState(() {
      loading = false;
      failed = draft.loadFailed;
    });
    if (!failed) draft.start();
  }

  void change(VoidCallback action) {
    setState(() {
      action();
      showErrorsClear();
    });
    draft.changed();
  }

  void showErrorsClear() {
    nameError = null;
    quantityError = null;
    costError = null;
    finenessError = null;
    locationError = null;
    dateError = null;
    error = null;
  }

  @override
  void dispose() {
    draft.close();
    for (final c in [name, quantity, cost, fineness, location]) {
      c.dispose();
    }
    super.dispose();
  }

  /// A price for the same asset and day that is not the record being edited.
  Quote? get sameDayQuote {
    if (isHolding || isGoal) return null;
    final current = market;
    return widget.quotes
        .where(
          (q) =>
              q.market.key == current.key &&
              q.date == date &&
              q.record.id != (widget.original?.id ?? ''),
        )
        .firstOrNull;
  }

  String quoteUnitHint() => switch (market.type) {
    AssetType.gold => s('quoteUnitGold'),
    AssetType.coin => s('quoteUnitCoin'),
    AssetType.currency => s('quoteUnitCurrency', {
      'code': currencyName(context, market.code),
    }),
    AssetType.other => s('quoteUnitOther'),
  };

  bool validate() {
    nameError = null;
    quantityError = null;
    costError = null;
    finenessError = null;
    locationError = null;
    dateError = null;
    error = null;
    if (isGoal) {
      if (!validName(name.text.trim())) nameError = 'enterName';
      final target = parseMoney(quantity.text, 3);
      if (!positive(target, 1000000000)) quantityError = 'enterTarget';
      setState(() {});
      return nameError == null && quantityError == null;
    }

    final current = market;
    final publishedMarket = {
      ...current.fields,
      if (!current.custom) 'name': '',
    };
    if (AssetMarket.read(publishedMarket) == null) {
      nameError = 'enterName';
    }
    final price = parseAmount(cost.text, 'IRR', 0, unit);
    if (isHolding) {
      final amount = parseMoney(quantity.text, current.digits);
      if (!positive(amount, 1000000000)) quantityError = 'enterQuantity';
      if (isGold && !positive(parseMoney(fineness.text, 0), 1000)) {
        finenessError = 'enterFineness';
      } else if (isGold) {
        final ppt = parseMoney(fineness.text, 0)!;
        if (ppt < 100) finenessError = 'enterFineness';
      }
      if (price == null || price < 0) {
        costError = 'enterCost';
      }
      if (custody == Custody.platform && !validName(location.text.trim())) {
        locationError = 'enterLocation';
      }
      if (date.isAfter(civilDay(DateTime.now()))) {
        dateError = 'invalidDate';
        detailsOpen = true;
      }
    } else if (!positive(price)) {
      costError = 'enterPrice';
    } else if (date.isAfter(civilDay(DateTime.now()))) {
      dateError = 'invalidDate';
    }
    if (locationError != null || dateError != null) detailsOpen = true;
    setState(() {});
    return nameError == null &&
        quantityError == null &&
        costError == null &&
        finenessError == null &&
        locationError == null &&
        dateError == null;
  }

  Fields? values() {
    if (isGoal) {
      final target = parseMoney(quantity.text, 3);
      if (!validName(name.text.trim()) || !positive(target, 1000000000)) {
        return null;
      }
      return {'title': name.text.trim(), 'targetMg': target};
    }
    final m = market;
    final publishedMarket = {...m.fields, if (!m.custom) 'name': ''};
    if (AssetMarket.read(publishedMarket) == null ||
        date.isAfter(civilDay(DateTime.now()))) {
      return null;
    }
    final price = parseAmount(cost.text, 'IRR', 0, unit);
    if (!isHolding) {
      if (!positive(price)) return null;
      return {
        ...publishedMarket,
        'date': date.toIso8601String(),
        'unitRial': price,
      };
    }
    final amount = parseMoney(quantity.text, m.digits);
    final ppt = isGold ? parseMoney(fineness.text, 0) : 750;
    if (!positive(amount, 1000000000) ||
        !positive(ppt, 1000) ||
        (isGold && ppt! < 100) ||
        price == null ||
        price < 0 ||
        !validName(location.text.trim(), empty: custody != Custody.platform)) {
      return null;
    }
    return {
      ...publishedMarket,
      'quantity': type == AssetType.currency ? null : amount,
      'amount': type == AssetType.currency ? amount : null,
      'currency': type == AssetType.currency ? m.code : null,
      'bought': date.toIso8601String(),
      'fineness': ppt,
      'costPerUnitRial': price,
      'custody': custody.name,
      'location': location.text.trim(),
    };
  }

  Future<void> submit() async {
    if (busy || !widget.revealed.value) return;
    if (!committed && !validate()) {
      setState(() => error = 'invalid');
      return;
    }
    final data = committed ? const <String, Object?>{} : values();
    if (data == null) {
      setState(() => error = 'invalid');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!committed) {
        await widget.save(id, {'v': 1, ...data});
        committed = true;
      }
      if (await draft.clear()) {
        if (mounted) Navigator.pop(context);
      } else if (mounted) {
        setState(() => error = 'saveError');
      }
    } on Object {
      if (mounted) setState(() => error = 'saveError');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => NexModuleCalendar(
    solar: NexModuleStrings.persian(context),
    child: DraftGuard(
      draft: draft,
      busy: () => loading || busy,
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.revealed,
        builder: (context, visible, _) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: visible
                ? editor(context)
                : FilledButton.icon(
                    onPressed: () => widget.revealed.value = true,
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(s('reveal')),
                  ),
          ),
        ),
      ),
    ),
  );

  Widget editor(BuildContext context) {
    final title = switch (widget.kind) {
      'holding' => holding == null ? 'newHolding' : 'editHolding',
      'quote' => quote == null ? 'newQuote' : 'editQuote',
      _ => goal == null ? 'newGoal' : 'editGoal',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s(title), style: Theme.of(context).textTheme.titleLarge),
        if (!isHolding && !isGoal) ...[
          const SizedBox(height: NexSpacing.xs),
          Text(
            marketLabel(context, market, forQuote: true),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(quoteUnitHint(), style: Theme.of(context).textTheme.bodySmall),
        ],
        if (loading)
          const Padding(
            padding: EdgeInsets.only(top: NexSpacing.md),
            child: LinearProgressIndicator(),
          )
        else if (failed) ...[
          Text(s('loadError')),
          TextButton(
            onPressed: () {
              setState(() => loading = true);
              unawaited(load());
            },
            child: Text(s('retry')),
          ),
        ] else ...[
          Flexible(
            child: SingleChildScrollView(
              child: AbsorbPointer(
                absorbing: busy || committed,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final field in fields(context))
                      Padding(
                        padding: const EdgeInsets.only(top: NexSpacing.md),
                        child: field,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (error != null && error != 'invalid')
            Padding(
              padding: const EdgeInsets.only(top: NexSpacing.sm),
              child: Text(
                s(error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: NexSpacing.sm),
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(s(committed ? 'retry' : 'save')),
          ),
        ],
      ],
    );
  }
}
