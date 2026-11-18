import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'history_status.dart';
import 'money_render.dart';
import 'lens_widgets.dart' show unitWordOf;
import 'options.dart';
import 'privacy.dart';
import 'product_actions.dart';
import 'products.dart';
import 'price_lens_common.dart';
import 'strings.dart';

class LensProductPage extends StatefulWidget {
  const LensProductPage({
    super.key,
    required this.controller,
    required this.productKey,
  });
  final PriceLensController controller;
  final String productKey;
  @override
  State<LensProductPage> createState() => _LensProductPageState();
}

class _LensProductPageState extends State<LensProductPage> {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = priceLensStrings, today = DateTime.now(), c = widget.controller;
    final product = productHistory(c.memories)
        .where((p) => p.key == widget.productKey)
        .firstOrNull;
    final latest = product?.latestKnown(today);
    return Scaffold(
      appBar: NexAppBar(
        title: Text(product?.label ?? s(context, 'productsTab')),
        actions: [
          const LensPrivacyButton(),
          if (product != null)
            IconButton(
              tooltip: s(context, 'share'),
              onPressed: () => unawaited(shareProduct(context, product)),
              icon: const Icon(Icons.share_outlined),
            ),
        ],
      ),
      floatingActionButton: product == null
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              key: const ValueKey('lens-add-price'),
              onPressed: () => unawaited(addProductPrice(context, c, product)),
              icon: const Icon(Icons.add),
              label: Text(s(context, 'newPrice')),
            ),
      body: c.readFailed
          ? LensReadError(controller: c)
          : product == null
          ? NexEmptyState(
              icon: Icons.history,
              message: s(context, 'productsNone'),
              action: TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: Text(s(context, 'productsTab')),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(NexSpacing.md),
              children: [
                if (latest != null) ...[
                  NexModuleHero(
                    moduleId: 'price_lens',
                    icon: Icons.receipt_long_outlined,
                    eyebrow: s(context, 'latestKnown'),
                    headline: lensMoney(
                      context,
                      latest.exactPaid,
                      latest.currency,
                    ),
                    caption:
                        '${memoryQuantity(context, latest)}${lensSep(context)}${lensFullDate(context, latest.date)}',
                  ),
                  const SizedBox(height: NexSpacing.md),
                  NexPanel(
                    title: s(context, 'unitTrend'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${lensMoney(context, memoryUnitPrice(latest, product.common), product.currency)} / ${unitWordOf(context, product.common.key)}',
                        ),
                        Text(
                          lensAmountsHidden(context)
                              ? '••••'
                              : memoryChangeLabel(context, product, today),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (product.previousDay(latest) case final previous?)
                          if (memoryQuantity(
                                context,
                                previous,
                                inUnit: product.common,
                              ) !=
                              memoryQuantity(
                                context,
                                latest,
                                inUnit: product.common,
                              ))
                            Text(
                              s(context, 'packChanged', {
                                'before': memoryQuantity(
                                  context,
                                  previous,
                                  inUnit: product.common,
                                ),
                                'after': memoryQuantity(
                                  context,
                                  latest,
                                  inUnit: product.common,
                                ),
                              }),
                            ),
                        Text(s(context, 'priceComparisonNote')),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: NexSpacing.md),
                NexShelfHeading(
                  icon: Icons.history,
                  title: s(context, 'priceHistory'),
                ),
                for (final memory in product.prices.reversed)
                  _HistoryPriceRow(
                    memory: memory,
                    controller: c,
                    future: priceDay(memory.date).isAfter(priceDay(today)),
                  ),
                const SizedBox(height: kMinInteractiveDimension * 2),
              ],
            ),
    );
  }
}

class _HistoryPriceRow extends StatelessWidget {
  const _HistoryPriceRow({
    required this.memory,
    required this.controller,
    required this.future,
  });
  final PriceMemory memory;
  final PriceLensController controller;
  final bool future;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: NexSpacing.sm),
    child: NexPanel(
      title: lensFullDate(context, memory.date),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  lensMoney(context, memory.exactPaid, memory.currency),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: priceLensStrings(context, 'delete'),
                onPressed: () =>
                    unawaited(forgetProductPrice(context, controller, memory)),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Text(memoryQuantity(context, memory)),
          if (memory.shop.isNotEmpty)
            NexTextDirection(text: memory.shop, child: Text(memory.shop)),
          if (future) Text(priceLensStrings(context, 'dateNeedsReview')),
        ],
      ),
    ),
  );
}
