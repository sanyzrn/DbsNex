/// The input side of the calculator: the piece, the rate, the charges and
/// the extras. Owns every controller, parses on each keystroke, and hands
/// the parent a [GoldInput] — or null while a field holds nonsense. The
/// panels themselves are laid out in `gold_form_panels.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_form_panels.dart';
import 'gold_fields.dart';
import 'gold_details.dart';
import 'gold_format.dart';
import 'gold_math.dart';
import 'gold_models.dart';
import 'gold_strings.dart';
import 'form_draft.dart';
import 'draft_guard.dart';
part 'gold_form_logic.dart';
part 'gold_form_draft.dart';

/// Toman with two decimals → whole rials, rounded to the nearest rial
/// (halves up). The one place a typed toman amount becomes the module's
/// stored unit; the receipt shows the rounded line.
int _toRial(int centiToman) =>
    centiToman ~/ 10 + (centiToman % 10 >= 5 ? 1 : 0);

/// The state of [GoldForm], reachable through a `GlobalKey` by the screen
/// that saves the estimate.
class GoldForm extends StatefulWidget {
  const GoldForm({
    super.key,
    required this.onInputChanged,
    this.initialQuote,
    required this.store,
    required this.metadata,
    required this.recordId,
    required this.busy,
    this.receipt,
  });
  final NexModuleStore store;
  final Map<String, TextEditingController> metadata;
  final String recordId;
  final bool Function() busy;
  final Widget? receipt;

  /// Fires with the current input whenever it changes; null while invalid.
  final ValueChanged<GoldInput?> onInputChanged;

  /// A saved quote the form opens filled with.
  final GoldQuote? initialQuote;

  @override
  State<GoldForm> createState() => GoldFormState();
}

class GoldFormState extends State<GoldForm>
    with AutomaticKeepAliveClientMixin<GoldForm>, _GoldFormLogic {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final strings = goldStrings;
    return DraftGuard(
      draft: _draft!,
      busy: () => widget.busy(),
      child: AbsorbPointer(
        absorbing: _restoring || widget.busy(),
        child: _draftLoadFailed
            ? NexEmptyState(
                icon: Icons.cloud_off_outlined,
                message: goldStrings(context, 'draftLoadError'),
                action: TextButton(
                  onPressed: () => unawaited(_restoreGoldDraft(this)),
                  child: Text(goldStrings(context, 'retry')),
                ),
              )
            : Column(
                children: [
                  NexPanel(
                    title: strings(context, 'purchaseBasics'),
                    icon: Icons.diamond_outlined,
                    child: Column(
                      children: [
                        GoldNumberField(
                          fieldKey: const ValueKey('gold-weight'),
                          label: strings(context, 'weight'),
                          suffix: strings(context, 'weightSuffix'),
                          controller: _weight,
                          scale: 3,
                          maxScaled: GoldInput.maxWeightMg,
                          allowEmpty: false,
                        ),
                        const SizedBox(height: NexSpacing.md),
                        GoldNumberField(
                          fieldKey: const ValueKey('gold-rate'),
                          label: strings(context, 'rate'),
                          controller: _rate,
                          scale: 2,
                          maxScaled: GoldInput.maxRateCenti,
                          allowEmpty: false,
                        ),
                        const SizedBox(height: NexSpacing.md),
                        goldMakingFields(
                          context,
                          mode: _mode,
                          onMode: (value) {
                            setState(() => _mode = value);
                            _changed();
                          },
                          makingPercent: _makingPercent,
                          makingPerGram: _makingPerGram,
                          makingFixed: _makingFixed,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  if (widget.receipt != null) ...[
                    widget.receipt!,
                    const SizedBox(height: NexSpacing.md),
                  ],
                  GoldDetails(
                    open: _detailsOpen,
                    toggleKey: const ValueKey('gold-purchase-details'),
                    title: strings(context, 'purchaseDetails'),
                    hint: strings(context, 'purchaseAssumptions', {
                      'ppt': _fineness,
                      'ref': _rateRef,
                      'profit': formatPercent(
                        parseScaled(_profit.text, 2) ?? 0,
                        persian: NexModuleStrings.persian(context),
                      ),
                      'vat': formatPercent(
                        parseScaled(_vat.text, 2) ?? 0,
                        persian: NexModuleStrings.persian(context),
                      ),
                    }),
                    onChanged: (value) => setState(() => _detailsOpen = value),
                    child: Column(
                      children: [
                        NexPanel(
                          title: strings(context, 'panelPiece'),
                          icon: Icons.scale_outlined,
                          child: goldPiecePanel(
                            context,
                            weight: _weight,
                            includeWeight: false,
                            gross: _gross,
                            fineness: _fineness,
                            onFineness: (ppt) {
                              setState(() => _fineness = ppt);
                              _changed();
                            },
                          ),
                        ),
                        const SizedBox(height: NexSpacing.md),
                        NexPanel(
                          title: strings(context, 'panelRate'),
                          icon: Icons.price_change_outlined,
                          child: goldRatePanel(
                            context,
                            rate: _rate,
                            includeRate: false,
                            rateRef: _rateRef,
                            onRateRef: (ppt) {
                              setState(() => _rateRef = ppt);
                              _changed();
                            },
                          ),
                        ),
                        const SizedBox(height: NexSpacing.md),
                        NexPanel(
                          title: strings(context, 'panelCharges'),
                          icon: Icons.construction_outlined,
                          child: goldChargesPanel(
                            context,
                            mode: _mode,
                            includeMaking: false,
                            onMode: (mode) {
                              setState(() => _mode = mode);
                              _changed();
                            },
                            profitBase: _profitBase,
                            onProfitBase: (value) {
                              setState(() => _profitBase = value);
                              _changed();
                            },
                            onReference: () {
                              _profitBase = GoldProfitBase.metalAndMaking;
                              _commissionTaxable = true;
                              _profit.text = '7';
                              _vat.text = '10';
                              _changed();
                            },
                            commissionTaxable: _commissionTaxable,
                            onCommissionTaxable: (value) {
                              setState(() => _commissionTaxable = value);
                              _changed();
                            },
                            makingPercent: _makingPercent,
                            makingPerGram: _makingPerGram,
                            makingFixed: _makingFixed,
                            profit: _profit,
                            vat: _vat,
                            commission: _commission,
                          ),
                        ),
                        const SizedBox(height: NexSpacing.md),
                        NexPanel(
                          title: strings(context, 'panelExtras'),
                          icon: Icons.add_circle_outline,
                          child: goldExtrasPanel(
                            context,
                            extras: _extras,
                            onAddExtra: () => _addExtra(),
                            onRemoveExtra: _removeExtra,
                            shopQuote: _shopQuote,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
