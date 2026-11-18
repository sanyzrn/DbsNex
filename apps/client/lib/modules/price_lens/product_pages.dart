import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'history_status.dart';
import 'money_render.dart';
import 'privacy.dart';
import 'product_actions.dart';
import 'product_detail.dart';
import 'products.dart';
import 'price_lens_common.dart';
import 'rational.dart';
import 'strings.dart';

class LensProductsPage extends StatefulWidget {
  const LensProductsPage({
    super.key,
    required this.controller,
    required this.onCompare,
    this.shopping = false,
  });
  final PriceLensController controller;
  final VoidCallback onCompare;
  final bool shopping;
  @override
  State<LensProductsPage> createState() => _LensProductsPageState();
}

class _LensProductsPageState extends State<LensProductsPage> {
  final _search = TextEditingController(), _scroll = ScrollController();
  final _busy = <String>{};
  bool _neededOnly = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bought(LensProduct product, bool bought) async {
    if (_busy.contains(product.key)) return;
    setState(() => _busy.add(product.key));
    try {
      await widget.controller.setBought(product.key, bought);
    } catch (_) {
      if (mounted) lensWriteFailure(context);
    } finally {
      if (mounted) setState(() => _busy.remove(product.key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, s = priceLensStrings, today = DateTime.now();
    if (c.loading) return const Center(child: CircularProgressIndicator());
    if (c.readFailed) return LensReadError(controller: c);
    final all = productHistory(c.memories);
    if (all.isEmpty) {
      return NexEmptyState(
        icon: Icons.shopping_bag_outlined,
        message: s(context, widget.shopping ? 'shoppingNone' : 'productsNone'),
        action: FilledButton.icon(
          onPressed: widget.onCompare,
          icon: const Icon(Icons.compare_arrows),
          label: Text(s(context, 'compareTab')),
        ),
      );
    }
    final query = productNameKey(_search.text);
    final rows = all
        .where(
          (p) =>
              productNameKey(p.label).contains(query) &&
              (!widget.shopping || !_neededOnly || !c.bought(p.key)),
        )
        .toList();
    final totals = <String, Fraction>{};
    if (widget.shopping) {
      for (final p in all.where((p) => !c.bought(p.key))) {
        final latest = p.latestKnown(today);
        if (latest != null) {
          totals.update(
            p.currency,
            (v) => v + latest.exactPaid,
            ifAbsent: () => latest.exactPaid,
          );
        }
      }
    }
    return ListView(
      key: ValueKey(
        widget.shopping ? 'lens-shopping-list' : 'lens-product-list',
      ),
      controller: _scroll,
      padding: const EdgeInsets.all(NexSpacing.md),
      children: [
        NexModuleHero(
          moduleId: 'price_lens',
          icon: widget.shopping ? Icons.shopping_bag_outlined : Icons.history,
          eyebrow: s(context, widget.shopping ? 'shoppingTab' : 'productsTab'),
          headline: s(
            context,
            widget.shopping ? 'shoppingRemaining' : 'productsCount',
            {
              'n': widget.shopping
                  ? all.where((p) => !c.bought(p.key)).length
                  : all.length,
            },
          ),
          caption: s(context, 'estimateOnly'),
        ),
        if (totals.isNotEmpty) ...[
          const SizedBox(height: NexSpacing.md),
          NexPanel(
            title: s(context, 'estimateTitle'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in totals.entries)
                  Text(lensMoney(context, e.value, e.key)),
                Text(s(context, 'estimateHint')),
              ],
            ),
          ),
        ],
        const SizedBox(height: NexSpacing.md),
        NexSearchField(
          controller: _search,
          hintText: s(context, 'productsSearch'),
          onChanged: (_) => setState(() {}),
        ),
        if (widget.shopping) ...[
          const SizedBox(height: NexSpacing.md),
          NexAdaptiveSegments<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(s(context, 'allProducts')),
              ),
              ButtonSegment(value: true, label: Text(s(context, 'neededOnly'))),
            ],
            selected: {_neededOnly},
            onSelectionChanged: (v) => setState(() => _neededOnly = v.first),
          ),
        ],
        const SizedBox(height: NexSpacing.md),
        if (rows.isEmpty) Text(s(context, 'productsNoResults')),
        for (final p in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.sm),
            child: NexPanel(
              child: InkWell(
                onTap: () => Navigator.of(context).push<void>(
                  NexPageRoute(
                    builder: lensRouteBuilder(
                      context,
                      LensProductPage(controller: c, productKey: p.key),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(NexSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (widget.shopping)
                            Checkbox(
                              value: c.bought(p.key),
                              onChanged: _busy.contains(p.key)
                                  ? null
                                  : (v) => unawaited(_bought(p, v!)),
                            ),
                          Expanded(
                            child: NexTextDirection(
                              text: p.label,
                              child: Text(
                                p.label,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      if (p.latestKnown(today) case final latest?) ...[
                        Text(
                          lensMoney(context, latest.exactPaid, latest.currency),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${memoryQuantity(context, latest)} · ${lensFullDate(context, latest.date)}',
                        ),
                        if (latest.shop.isNotEmpty)
                          NexTextDirection(
                            text: latest.shop,
                            child: Text(latest.shop),
                          ),
                        Text(
                          lensAmountsHidden(context)
                              ? '••••'
                              : memoryChangeLabel(context, p, today),
                        ),
                      ] else
                        Text(s(context, 'dateNeedsReview')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: kMinInteractiveDimension * 2),
      ],
    );
  }
}
