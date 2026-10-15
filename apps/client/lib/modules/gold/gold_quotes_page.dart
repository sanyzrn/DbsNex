/// Saved estimates: the list, delete-with-Undo, and picking two to
/// compare. The detail sheet lives in `gold_quote_sheet.dart` and the
/// comparison itself in `gold_compare_page.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_compare_page.dart';
import 'gold_format.dart';
import 'gold_models.dart';
import 'gold_quote_sheet.dart';
import 'gold_screen.dart';
import 'gold_strings.dart';
import 'record_bundle.dart';

class GoldQuotesPage extends StatefulWidget {
  const GoldQuotesPage({
    super.key,
    required this.store,
    required this.showRials,
  });

  final NexModuleStore store;
  final bool showRials;

  @override
  State<GoldQuotesPage> createState() => _GoldQuotesPageState();
}

class _GoldQuotesPageState extends State<GoldQuotesPage>
    with WidgetsBindingObserver {
  List<GoldQuote> _quotes = const [];
  StreamSubscription<void>? _changes;
  bool _loading = true;
  bool _comparing = false;
  bool _failed = false;
  bool _deleting = false;
  int _generation = 0;
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      await RecordBundle.recover(widget.store);
      final records = await widget.store.list('quote');
      if (!mounted || generation != _generation) return;
      setState(() {
        _quotes = [
          for (final record in records)
            GoldQuote.fromRecord(record.id, record.body),
        ];
        _loading = false;
        _failed = false;
        _picked.removeWhere((id) => !_quotes.any((quote) => quote.id == id));
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  void _toggleCompare() {
    setState(() {
      _comparing = !_comparing;
      if (!_comparing) _picked.clear();
    });
  }

  void _pick(GoldQuote quote) {
    setState(() {
      if (_picked.contains(quote.id)) {
        _picked.remove(quote.id);
      } else {
        _picked.add(quote.id);
      }
    });
    if (_picked.length == 2) {
      final pair = _quotes
          .where((quote) => _picked.contains(quote.id))
          .toList();
      if (pair.length == 2) {
        setState(() {
          _comparing = false;
          _picked.clear();
        });
        Navigator.of(context).push(
          NexPageRoute<void>(
            builder: (_) => GoldComparePage(
              first: pair[0],
              second: pair[1],
              showRials: widget.showRials,
            ),
          ),
        );
      }
    }
  }

  Future<void> _openQuote(GoldQuote quote) async {
    final result = await showGoldQuoteSheet(
      context,
      quote: quote,
      showRials: widget.showRials,
    );
    if (!mounted) return;
    if (result == 'edit') {
      Navigator.of(context).push(
        NexPageRoute<void>(
          builder: (_) => GoldScreen(store: widget.store, editing: quote),
        ),
      );
    } else if (result == 'delete') {
      await _delete(quote);
    }
  }

  Future<void> _delete(GoldQuote quote) async {
    final confirmed = await nexShowDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(goldStrings(dialogContext, 'deleteQuoteTitle')),
        content: NexDialogBody(
          child: Text(goldStrings(dialogContext, 'deleteQuoteBody')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(dialogContext).cancel),
          ),
          TextButton(
            key: const ValueKey('gold-delete-confirm'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, 'delete'),
            child: Text(AppLocalizations.of(dialogContext).delete),
          ),
        ],
      ),
    );
    if (confirmed != 'delete' || !mounted) return;

    if (_deleting) return;
    _deleting = true;
    late RecordBundle bundle;
    try {
      bundle = await RecordBundle.capture(
        widget.store,
        'quote',
        quote.id,
        'unused',
        'quoteId',
      );
      await bundle.delete();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(goldStrings(context, 'quoteSaveFailed'))),
        );
      }
      return;
    } finally {
      _deleting = false;
    }
    if (!mounted) return;
    // The Undo is time-limited and restores the whole record, exactly as
    // it was, under its own id.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(goldStrings(context, 'quoteDeleted')),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: AppLocalizations.of(context).undo,
          onPressed: () => unawaited(_restore(bundle)),
        ),
      ),
    );
  }

  Future<void> _restore(RecordBundle bundle) async {
    try {
      await bundle.restore();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(goldStrings(context, 'quoteRestored'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(goldStrings(context, 'quoteSaveFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = goldStrings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings(context, 'savedQuotes')),
        actions: [
          if (_quotes.length >= 2)
            IconButton(
              key: const ValueKey('gold-compare-toggle'),
              tooltip: strings(context, 'compare'),
              onPressed: _toggleCompare,
              icon: Icon(_comparing ? Icons.close : Icons.compare_arrows),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? NexEmptyState(
              icon: Icons.cloud_off_outlined,
              message: strings(context, 'loadError'),
              action: TextButton(
                onPressed: () => unawaited(_load()),
                child: Text(strings(context, 'retry')),
              ),
            )
          : _quotes.isEmpty
          ? NexEmptyState(
              icon: Icons.inventory_2_outlined,
              message: strings(context, 'savedQuotesEmpty'),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
              children: [
                const SizedBox(height: NexSpacing.md),
                if (_comparing)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      bottom: NexSpacing.sm,
                    ),
                    child: Text(
                      strings(context, 'comparePick'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (var i = 0; i < _quotes.length; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      bottom: NexSpacing.sm,
                    ),
                    child: _QuoteRow(
                      quote: _quotes[i],
                      showRials: widget.showRials,
                      comparing: _comparing,
                      picked: _picked.contains(_quotes[i].id),
                      onTap: () => _comparing
                          ? _pick(_quotes[i])
                          : unawaited(_openQuote(_quotes[i])),
                    ),
                  ),
                const SizedBox(height: NexSpacing.xl),
              ],
            ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({
    required this.quote,
    required this.showRials,
    required this.comparing,
    required this.picked,
    required this.onTap,
  });

  final GoldQuote quote;
  final bool showRials;
  final bool comparing;
  final bool picked;
  final VoidCallback onTap;

  String _whenWords(BuildContext context, String savedAtIso) {
    final strings = goldStrings;
    final saved = DateTime.tryParse(savedAtIso);
    if (saved == null) return savedAtIso;
    return relativeDayWords(
      saved,
      DateTime.now(),
      today: () => strings(context, 'whenToday'),
      yesterday: () => strings(context, 'whenYesterday'),
      daysAgo: (days) => strings(context, 'whenDaysAgo', {'n': days}),
      onDate: (date) => strings(context, 'whenDate', {
        'date': goldDigits(date, NexModuleStrings.persian(context)),
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = goldStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final money = formatRial(
      quote.estimatedTotalRial,
      persian: persian,
      rials: showRials,
    );
    final title = quote.title.isEmpty
        ? strings(context, 'receipt')
        : quote.title;
    final savedWhen = _whenWords(context, quote.savedAtIso);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(NexRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: comparing
            ? Icon(
                picked ? Icons.check_box : Icons.check_box_outline_blank,
                color: theme.colorScheme.primary,
              )
            : const Icon(Icons.receipt_long_outlined),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (quote.shop.isNotEmpty)
              Text(
                quote.shop,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            Text(
              '${strings(context, 'savedOn', {'when': savedWhen})} · '
              '${formatWeightMg(quote.input.weightMg, persian: persian)} '
              '${strings(context, 'weightSuffix')} · '
              '${groupDigits(quote.input.finenessPpt, persian: persian)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '$money ${strings(context, showRials ? 'showRial' : 'showToman')}',
              textDirection: TextDirection.ltr,
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
