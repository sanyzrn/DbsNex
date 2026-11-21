/// Gold Check's own screen: the calculator, its receipt, and the one
/// primary action — saving the estimate as it stands, with the day's date
/// and the rates that went into it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_budget_sheet.dart';
import 'gold_form.dart';
import 'gold_format.dart';
import 'gold_guide.dart';
import 'gold_math.dart';
import 'gold_market_page.dart';
import 'gold_workspace.dart';
import 'gold_models.dart';
import 'gold_tabs.dart';
import 'gold_quotes_page.dart';
import 'gold_receipt.dart';
import 'draft_guard.dart';
import 'gold_save_sheet.dart';
import 'gold_strings.dart';

class GoldScreen extends StatefulWidget {
  const GoldScreen({super.key, required this.store, this.editing});

  final NexModuleStore store;

  /// A saved quote to edit; null for a fresh estimate.
  final GoldQuote? editing;

  @override
  State<GoldScreen> createState() => _GoldScreenState();
}

class _GoldScreenState extends State<GoldScreen> {
  late bool _showRials;
  GoldInput? _input;
  bool _saving = false;
  bool _saved = false;
  late final String _recordId;
  bool _howOpen = false;

  /// Buy, sell or melted gold: the destination on show (2.8.2).
  int _tab = 0;

  final _marketKey = GlobalKey<GoldMarketPanelState>();
  final _formKey = GlobalKey<GoldFormState>();
  final _title = TextEditingController();
  final _shop = TextEditingController();
  final _quoteDate = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _showRials = false;
    _recordId = widget.editing?.id ?? widget.store.newId();
    final editing = widget.editing;
    if (editing != null) {
      _title.text = editing.title;
      _shop.text = editing.shop;
      _quoteDate.text = editing.quoteDateIso;
      _notes.text = editing.notes;
    } else {
      _quoteDate.text = DateTime.now().toIso8601String().substring(0, 10);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _shop.dispose();
    _quoteDate.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = _formKey.currentState;
    final input = state?.buildInput();
    if (state == null || input == null || _saving) return;
    setState(() => _saving = true);
    final confirmed = await showGoldSaveSheet(
      context,
      title: _title,
      shop: _shop,
      quoteDate: _quoteDate,
      notes: _notes,
      editing: widget.editing != null || _saved,
    );
    if (!mounted) return;
    if (!confirmed) {
      setState(() => _saving = false);
      return;
    }
    final result = GoldMath.calculate(input);

    setState(() => _saving = true);
    final id = _recordId;
    final quote = GoldQuote(
      id: id,
      title: _title.text.trim(),
      shop: _shop.text.trim(),
      savedAtIso: DateTime.now().toIso8601String(),
      quoteDateIso: normalizeGoldDate(_quoteDate.text),
      notes: _notes.text.trim(),
      input: input,
      metalValueRial: result.metalValueRial,
      makingChargeRial: result.makingChargeRial,
      sellerProfitRial: result.sellerProfitRial,
      commissionRial: result.commissionRial,
      vatBaseRial: result.vatBaseRial,
      vatRial: result.vatRial,
      extrasRial: result.extrasRial,
      estimatedTotalRial: result.estimatedTotalRial,
    );
    try {
      final prior = await widget.store.get('quote', id);
      await widget.store.put('quote', id, {...?prior, ...quote.toRecord()});
      await state.markSaved(quote);
      if (mounted) setState(() => _saved = true);
      if (!mounted) return;
      NexBannerHost.of(context)
          ?.show(message: goldStrings(context, 'quoteSaved'));
    } catch (_) {
      if (!mounted) return;
      NexBannerHost.of(context)?.show(
        kind: NexBannerKind.failed,
        message: goldStrings(context, 'quoteSaveFailed'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// «From a budget»: the calculator run backwards. The rate and charges
  /// come from the form; when they are not yet valid, say so.
  Future<void> _fromBudget() async {
    final state = _formKey.currentState;
    final input = state?.buildInput(forBudget: true);
    if (state == null || _saving) return;
    if (input == null) {
      nexShowBanner(
        context,
        message: goldStrings(context, 'budgetNeedsRate'),
        kind: NexBannerKind.failed,
      );
      return;
    }
    final milligrams = await showGoldBudgetSheet(
      context,
      input: input,
      showRials: _showRials,
    );
    if (milligrams != null && milligrams > 0 && mounted) {
      state.setWeightMg(milligrams);
    }
  }

  Future<void> _discard() async {
    if (_saving || _formKey.currentState?.canDiscard != true) return;
    setState(() => _saving = true);
    try {
      final cleared = await _formKey.currentState?.discardDraft();
      if (cleared == false && mounted) {
        NexBannerHost.of(context)?.show(
          kind: NexBannerKind.failed,
          message: goldStrings(context, 'saveError'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = goldStrings;
    final theme = Theme.of(context);
    final editing = widget.editing != null;
    final input = _input;
    final result = input == null ? null : GoldMath.calculate(input);

    return DraftGuard(
      drafts: () => [
        ?_formKey.currentState?.draft,
        ?_marketKey.currentState?.draft,
      ],
      busy: () => _saving,
      child: Scaffold(
        appBar: NexAppBar(
          title: Text(strings(context, 'title')),
          actions: [
            // The rial/toman toggle: labelled with the unit in use, one tap
            // away from the other. Never a guess about which one is meant.
            Semantics(
              label: strings(context, 'unitToggleSemantics'),
              button: true,
              child: TextButton(
                key: const ValueKey('gold-unit-toggle'),
                onPressed: () => setState(() => _showRials = !_showRials),
                child: Text(
                  _showRials
                      ? strings(context, 'showRial')
                      : strings(context, 'showToman'),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('gold-open-budget'),
              tooltip: strings(context, 'budgetTip'),
              onPressed: _saving ? null : () => unawaited(_fromBudget()),
              icon: const Icon(Icons.savings_outlined),
            ),
            IconButton(
              key: const ValueKey('gold-open-quotes'),
              tooltip: strings(context, 'openSavedQuotesTip'),
              onPressed: () => Navigator.of(context).push(
                NexPageRoute<void>(
                  builder: (_) => GoldQuotesPage(
                    store: widget.store,
                    showRials: _showRials,
                  ),
                ),
              ),
              icon: const Icon(Icons.inventory_2_outlined),
            ),
          ],
        ),
        // Saving is a purchase estimate's; selling and melted gold are worked
        // out, not saved.
        floatingActionButton: _tab != 0
            ? null
            : FloatingActionButton.extended(
                // No hero: a page's button never flies into another's (2.8.2).
                heroTag: null,
                key: const ValueKey('gold-save-fab'),
                onPressed: _saving || input == null ? null : _save,
                label: Text(
                  strings(
                    context,
                    editing || _saved ? 'updateQuote' : 'saveQuote',
                  ),
                ),
                icon: const Icon(Icons.save_outlined),
              ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
          children: [
            const SizedBox(height: NexSpacing.md),
            GoldWorkspace(
              selected: _tab,
              onChanged: (tab) {
                if (tab == _tab) return;
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() => _tab = tab);
              },
            ),
            // Buy, and selling or melted gold, in place (2.8.2): both kept as
            // they were left, the one chosen fading in.
            GoldKeptTabs(
              index: _tab == 0 ? 0 : 1,
              builders: [
                (context) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: NexSpacing.sm),
                    Wrap(
                      spacing: NexSpacing.sm,
                      children: [
                        IconButton(
                          key: const ValueKey('gold-open-guide'),
                          tooltip: strings(context, 'openGuideTip'),
                          onPressed: () => Navigator.of(context).push(
                            NexPageRoute<void>(
                              builder: (_) => const GoldGuidePage(),
                            ),
                          ),
                          icon: const Icon(Icons.help_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    GoldForm(
                      key: _formKey,
                      initialQuote: widget.editing,
                      store: widget.store,
                      metadata: {
                        'title': _title,
                        'shop': _shop,
                        'quoteDate': _quoteDate,
                        'notes': _notes,
                      },
                      recordId: _recordId,
                      busy: () => _saving,
                      receipt: input != null && result != null
                          ? GoldReceipt(
                              input: input,
                              result: result,
                              showRials: _showRials,
                              quoteDate: _quoteDate.text.trim(),
                            )
                          : null,
                      onInputChanged: (input) {
                        if (mounted) setState(() => _input = input);
                      },
                    ),
                    if (!editing && !_saved)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const ValueKey('gold-discard-draft'),
                          onPressed:
                              _saving ||
                                  _formKey.currentState?.canDiscard != true
                              ? null
                              : _discard,
                          icon: const Icon(Icons.restart_alt),
                          label: Text(strings(context, 'discardDraft')),
                        ),
                      ),
                    if (editing || _saved) ...[
                      const SizedBox(height: NexSpacing.sm),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const ValueKey('gold-new-estimate'),
                          onPressed: () => Navigator.of(context).push(
                            NexPageRoute<void>(
                              builder: (_) => GoldScreen(store: widget.store),
                            ),
                          ),
                          icon: const Icon(Icons.add),
                          label: Text(strings(context, 'newEstimate')),
                        ),
                      ),
                    ],
                    const SizedBox(height: NexSpacing.md),
                    GoldHowCalculated(
                      open: _howOpen,
                      onToggle: () => setState(() => _howOpen = !_howOpen),
                    ),
                    const SizedBox(height: NexSpacing.md),
                    if (input == null)
                      Padding(
                        padding: const EdgeInsets.all(NexSpacing.md),
                        child: Text(
                          strings(context, 'fixFields'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                (context) => Padding(
                  padding: const EdgeInsets.only(top: NexSpacing.md),
                  child: GoldMarketPanel(
                    key: _marketKey,
                    store: widget.store,
                    mode: _tab == 0 ? 1 : _tab,
                    showRials: _showRials,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.xl * 2),
          ],
        ),
      ),
    );
  }
}
