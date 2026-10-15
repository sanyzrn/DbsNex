/// Gold Check's own screen: the calculator, its receipt, and the one
/// primary action — saving the estimate as it stands, with the day's date
/// and the rates that went into it.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_form.dart';
import 'gold_format.dart';
import 'gold_guide.dart';
import 'gold_math.dart';
import 'gold_models.dart';
import 'gold_quotes_page.dart';
import 'gold_receipt.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(goldStrings(context, 'quoteSaved'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(goldStrings(context, 'quoteSaveFailed'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard() async {
    if (_saving || _formKey.currentState?.canDiscard != true) return;
    setState(() => _saving = true);
    try {
      final cleared = await _formKey.currentState?.discardDraft();
      if (cleared == false && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(goldStrings(context, 'saveError'))),
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

    return Scaffold(
      appBar: AppBar(
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
            key: const ValueKey('gold-open-quotes'),
            tooltip: strings(context, 'openSavedQuotesTip'),
            onPressed: () => Navigator.of(context).push(
              NexPageRoute<void>(
                builder: (_) =>
                    GoldQuotesPage(store: widget.store, showRials: _showRials),
              ),
            ),
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            key: const ValueKey('gold-open-guide'),
            tooltip: strings(context, 'openGuideTip'),
            onPressed: () => Navigator.of(
              context,
            ).push(NexPageRoute<void>(builder: (_) => const GoldGuidePage())),
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('gold-save-fab'),
        onPressed: _saving || input == null ? null : _save,
        label: Text(
          strings(context, editing || _saved ? 'updateQuote' : 'saveQuote'),
        ),
        icon: const Icon(Icons.save_outlined),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
        children: [
          const SizedBox(height: NexSpacing.md),
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
            onInputChanged: (input) {
              if (mounted) setState(() => _input = input);
            },
          ),
          if (!editing && !_saved)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('gold-discard-draft'),
                onPressed: _saving || _formKey.currentState?.canDiscard != true
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
          if (input != null && result != null)
            GoldReceipt(
              input: input,
              result: result,
              showRials: _showRials,
              quoteDate: _quoteDate.text.trim(),
            )
          else
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
          const SizedBox(height: NexSpacing.xl * 2),
        ],
      ),
    );
  }
}
