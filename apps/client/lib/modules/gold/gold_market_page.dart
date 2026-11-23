import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'draft_guard.dart';
import 'form_draft.dart';
import 'gold_fields.dart';
import 'gold_details.dart';
import 'gold_format.dart';
import 'gold_market_math.dart';
import 'gold_market_result.dart';
import 'gold_math.dart';
import 'gold_strings.dart';
import 'gold_workspace.dart';

/// Sell and melted-gold tools share a checkpoint, but retain separate raw
/// inputs. A tab change never reinterprets a rate already entered elsewhere.
/// Selling and melted gold, as a page of its own — the panel below with the
/// three destinations over it. Gold's own screen hosts the same panel in
/// place (2.8.2); this page remains for a direct entry.
class GoldMarketPage extends StatefulWidget {
  const GoldMarketPage({
    super.key,
    required this.store,
    required this.mode,
    this.showRials = false,
  });
  final NexModuleStore store;
  final int mode;
  final bool showRials;
  @override
  State<GoldMarketPage> createState() => _GoldMarketPageState();
}

class _GoldMarketPageState extends State<GoldMarketPage> {
  late int _mode = widget.mode;
  late bool _rials = widget.showRials;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: NexAppBar(
      title: Text(goldStrings(context, 'title')),
      actions: [
        TextButton(
          onPressed: () => setState(() => _rials = !_rials),
          child: Text(goldStrings(context, _rials ? 'showRial' : 'showToman')),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(NexSpacing.md),
      children: [
        GoldWorkspace(
          selected: _mode,
          onChanged: (value) {
            FocusManager.instance.primaryFocus?.unfocus();
            if (value == 0) {
              Navigator.of(context).maybePop();
            } else {
              setState(() => _mode = value);
            }
          },
        ),
        const SizedBox(height: NexSpacing.md),
        GoldMarketPanel(
          store: widget.store,
          mode: _mode,
          showRials: _rials,
          guardExit: true,
        ),
      ],
    ),
  );
}

/// Selling and melted gold: the inputs, the result and the caution for the
/// [mode] chosen — 1 to sell, 2 for melted gold.
///
/// One form under both: what was typed for one stays when the other is
/// looked at, and both are kept as a draft. Switching between the two fades
/// the one into the other rather than replacing it on a frame (2.8.2).
class GoldMarketPanel extends StatefulWidget {
  const GoldMarketPanel({
    super.key,
    required this.store,
    required this.mode,
    this.showRials = false,
    this.guardExit = false,
  });
  final NexModuleStore store;
  final int mode;
  final bool showRials;
  final bool guardExit;
  @override
  GoldMarketPanelState createState() => GoldMarketPanelState();
}

class GoldMarketPanelState extends State<GoldMarketPanel> {
  int get _mode => widget.mode;
  bool get _rials => widget.showRials;
  bool _loading = true, _failed = false, _details = false;
  int _settlement = 750, _fineness = 750;
  bool _mithqal = true;
  final _fields = <String, TextEditingController>{
    for (final key in [
      'sellWeight',
      'sellRate',
      'deduction',
      'fee',
      'cost',
      'meltWeight',
      'meltQuote',
      'meltGram',
    ])
      key: switch (key) {
        'sellWeight' || 'deduction' || 'meltWeight' => TextEditingController(),
        _ => NexMoneyController(),
      },
  };
  late final FormDraft _draft;

  FormDraft get draft => _draft;

  @override
  void initState() {
    super.initState();
    _draft = FormDraft(
      widget.store,
      'market:tools',
      const {},
      _fields,
      () => {
        'settlement': _settlement,
        'fineness': _fineness,
        'mithqal': _mithqal,
      },
    );
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final body = await _draft.load();
    if (!mounted) return;
    if (_draft.loadFailed) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    if (body != null) {
      _draft.apply(body);
      final settlement = body['settlement'], fineness = body['fineness'];
      if (settlement is int && settlement >= 100 && settlement <= 999) {
        _settlement = settlement;
      }
      if (fineness is int && fineness >= 100 && fineness <= 999) {
        _fineness = fineness;
      }
      _mithqal = body['mithqal'] != false;
      _details = [
        'deduction',
        'fee',
        'cost',
      ].any((key) => _fields[key]!.text.isNotEmpty);
    }
    _draft.start();
    for (final controller in _fields.values) {
      controller.addListener(_changed);
    }
    setState(() {
      _loading = false;
      _failed = false;
    });
  }

  void _changed() {
    _draft.changed();
    setState(() {});
  }

  @override
  void dispose() {
    _draft.close();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _read(String key, int scale, int max, {bool required = false}) {
    final field = _fields[key]!;
    final text = field.text;
    if (text.trim().isEmpty) return required ? null : 0;
    final (value, error) = parseScaledDetailed(
      text,
      scale,
      grouped: field is NexMoneyController,
    );
    return error == null && value != null && value <= max ? value : null;
  }

  Widget _number(
    String key,
    String label,
    int scale,
    int max, {
    bool required = false,
  }) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.md),
    child: GoldNumberField(
      fieldKey: ValueKey('gold-$key'),
      label: goldStrings(context, label),
      controller: _fields[key]!,
      scale: scale,
      maxScaled: max,
      allowEmpty: !required,
      requirePositive: required,
    ),
  );

  Widget _inputs() {
    if (_mode == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _number(
            'sellWeight',
            'weight',
            3,
            GoldInput.maxWeightMg,
            required: true,
          ),
          _number(
            'sellRate',
            'marketRate750',
            2,
            GoldInput.maxRateCenti,
            required: true,
          ),
          GoldFinenessField(
            fieldKey: const ValueKey('gold-settlement'),
            presets: const [750, 740],
            label: goldStrings(context, 'settlement'),
            hint: goldStrings(context, 'settlementHint'),
            value: _settlement,
            onChanged: (value) {
              _settlement = value;
              _changed();
            },
          ),
          const SizedBox(height: NexSpacing.md),
          GoldDetails(
            open: _details,
            toggleKey: const ValueKey('gold-sale-details'),
            onChanged: (value) => setState(() => _details = value),
            title: goldStrings(context, 'saleDetails'),
            hint: goldStrings(context, 'saleDetailsHint'),
            child: Column(
              children: [
                _number('deduction', 'saleDeduction', 2, 10000),
                _number('fee', 'saleFee', 1, GoldInput.maxAmountRial),
                _number('cost', 'saleCost', 1, GoldInput.maxAmountRial),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexAdaptiveSegments<bool>(
          segments: [
            ButtonSegment(
              value: true,
              label: Text(goldStrings(context, 'mithqalQuote')),
            ),
            ButtonSegment(
              value: false,
              label: Text(goldStrings(context, 'gram750Quote')),
            ),
          ],
          selected: {_mithqal},
          onSelectionChanged: (values) {
            _mithqal = values.first;
            _changed();
          },
        ),
        const SizedBox(height: NexSpacing.md),
        if (_mithqal)
          _number(
            'meltQuote',
            'marketMithqal',
            2,
            GoldInput.maxRateCenti * 5,
            required: true,
          )
        else
          _number(
            'meltGram',
            'marketRate750',
            2,
            GoldInput.maxRateCenti,
            required: true,
          ),
        _number(
          'meltWeight',
          'weight',
          3,
          GoldInput.maxWeightMg,
          required: true,
        ),
        GoldFinenessField(
          fieldKey: const ValueKey('gold-melt-fineness'),
          presets: const [750, 705, 999],
          label: goldStrings(context, 'assayFineness'),
          hint: goldStrings(context, 'assayHint'),
          value: _fineness,
          onChanged: (value) {
            _fineness = value;
            _changed();
          },
        ),
      ],
    );
  }

  Widget _result() {
    final weight = _read(
      _mode == 1 ? 'sellWeight' : 'meltWeight',
      3,
      GoldInput.maxWeightMg,
      required: true,
    );
    final rate = _read(
      _mode == 1 ? 'sellRate' : (_mithqal ? 'meltQuote' : 'meltGram'),
      2,
      GoldInput.maxRateCenti * (_mode == 2 && _mithqal ? 5 : 1),
      required: true,
    );
    if (weight == null || rate == null || weight == 0 || rate == 0) {
      return _empty();
    }
    try {
      if (_mode == 1) {
        final deduction = _read('deduction', 2, 10000),
            fee = _read('fee', 1, GoldInput.maxAmountRial),
            cost = _read('cost', 1, GoldInput.maxAmountRial);
        if (deduction == null || fee == null || cost == null) return _empty();
        final sale = GoldMarketMath.sell(
          weightMg: weight,
          rate750Centi: rate,
          settlementPpt: _settlement,
          deductionBp: deduction,
          feeRial: fee,
        );
        return GoldMarketResult.sale(
          sale: sale,
          weightMg: weight,
          rateCenti: rate,
          settlement: _settlement,
          deductionBp: deduction,
          costRial: cost,
          showRials: _rials,
        );
      }
      final target = _mithqal
          ? GoldMarketMath.gramFromMithqal(rate, _fineness)
          : GoldMarketMath.rateAt(rate, 750, _fineness);
      // Converted rates must stay within the same per-gram range as purchases.
      if (target < 1) return _empty('convertedRateTooSmall');
      if (target > GoldInput.maxRateCenti) return _empty('parse_tooBig');
      return GoldMarketResult.melt(
        weightMg: weight,
        rateCenti: target,
        fineness: _fineness,
        mithqalCenti: _mithqal
            ? rate
            : GoldMarketMath.mithqalFromGram(rate, 750),
        showRials: _rials,
      );
    } on ArgumentError {
      return _empty('saleInvalid');
    }
  }

  Widget _empty([String key = 'marketEmpty']) => Padding(
    padding: const EdgeInsets.all(NexSpacing.md),
    child: Text(goldStrings(context, key), textAlign: TextAlign.center),
  );

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    return widget.guardExit
        ? DraftGuard(drafts: () => [_draft], busy: () => _loading, child: body)
        : body;
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(NexSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_failed) {
      return NexEmptyState(
        icon: Icons.refresh,
        message: goldStrings(context, 'draftLoadError'),
        action: TextButton(
          onPressed: _load,
          child: Text(goldStrings(context, 'retry')),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: NexMotion.of(context, NexMotion.standard),
      switchInCurve: NexMotion.curve,
      switchOutCurve: NexMotion.exitCurve,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: Column(
        key: ValueKey('gold-market-$_mode'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            goldStrings(context, _mode == 1 ? 'saleIntro' : 'meltIntro'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: NexSpacing.md),
          NexPanel(
            title: goldStrings(
              context,
              _mode == 1 ? 'saleInputs' : 'meltInputs',
            ),
            icon: _mode == 1 ? Icons.sell_outlined : Icons.balance_outlined,
            child: _inputs(),
          ),
          const SizedBox(height: NexSpacing.md),
          _result(),
          const SizedBox(height: NexSpacing.lg),
          Text(
            goldStrings(context, _mode == 1 ? 'saleCaution' : 'meltCaution'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
