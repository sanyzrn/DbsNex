part of 'lens_widgets.dart';

/// The result: which offer is actually cheaper, why, and by exactly
/// how much the others are not. Savings are relative to the cheapest
/// entered offer — never to a fabricated market baseline.
class LensResultPanel extends StatelessWidget {
  const LensResultPanel({
    super.key,
    required this.comparison,
    required this.commonUnit,
    required this.persian,
    required this.memoryLine,
  });

  final Comparison comparison;
  final PriceUnit commonUnit;
  final bool persian;
  final Widget? memoryLine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = priceLensStrings;
    final hue = NexHue.violet.of(theme.brightness);
    final unitWord = unitWordOf(context, commonUnit.key);

    if (comparison.state != ComparisonState.ready) {
      final message = switch (comparison.state) {
        ComparisonState.tooFewOptions => s(context, 'tooFew'),
        ComparisonState.mixedCurrencies => s(context, 'mixedCurrencies'),
        ComparisonState.mixedFamilies => s(context, 'notComparable'),
        ComparisonState.incompleteOption => s(context, 'incomplete'),
        ComparisonState.ready => '',
      };
      return NexPanel(
        title: s(context, 'title'),
        icon: Icons.calculate_outlined,
        child: Text(message, style: theme.textTheme.bodyMedium),
      );
    }

    final best = comparison.bestUnitPrice;
    final bestCount = comparison.results.where((r) => r.isBest).length;
    final rows = <Widget>[];
    for (final result in comparison.results) {
      rows.add(
        _ResultRow(
          result: result,
          best: best,
          unitWord: unitWord,
          persian: persian,
        ),
      );
    }
    final headline = _headline(context, unitWord);
    final bestLabel = comparison.results
        .where((r) => r.isBest)
        .map((r) => r.option.label.trim())
        .where((label) => label.isNotEmpty)
        .firstOrNull;
    // The winner leads, large, on the module's own colour; the sentence that
    // says by how much sits under it, then every offer in order.
    return NexModuleHero(
      key: const ValueKey('lens-hero'),
      moduleId: 'price_lens',
      icon: Icons.emoji_events_outlined,
      eyebrow: s(context, 'resultTitle', {'unit': unitWord}),
      headline: bestLabel ?? s(context, 'resultTitle', {'unit': unitWord}),
      caption: headline,
      captionKey: const ValueKey('lens-headline'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          if (bestCount > 1)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
              child: Text(
                s(context, 'tieNote', {'n': bestCount}),
                style: theme.textTheme.bodySmall?.copyWith(color: hue),
              ),
            ),
          const Divider(height: NexSpacing.lg),
          Text(
            s(context, 'smallestNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            s(context, 'priceComparisonNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (memoryLine != null) ...[
            const Divider(height: NexSpacing.lg),
            memoryLine!,
          ],
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            children: [
              TextButton.icon(
                onPressed: () => unawaited(_share(context, unitWord)),
                icon: const Icon(Icons.share_outlined),
                label: Text(s(context, 'share')),
              ),
              TextButton.icon(
                key: const ValueKey('lens-copy-result'),
                onPressed: () => unawaited(_copy(context, unitWord)),
                icon: const Icon(Icons.copy_outlined),
                label: Text(s(context, 'copyResult')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The answer in one sentence: the cheapest offer against the dearest, how
  /// much less per unit as a percentage of the dearer. Display only — the
  /// ranking above it is the exact fractions; this rounds to a tenth.
  String? _headline(BuildContext context, String unitWord) {
    if (lensAmountsHidden(context)) return null;
    final priced = [
      for (final r in comparison.results)
        if (r.unitPriceMinor != null) r,
    ];
    if (priced.length < 2) return null;
    final best = priced.reduce(
      (a, b) => a.unitPriceMinor! <= b.unitPriceMinor! ? a : b,
    );
    final worst = priced.reduce(
      (a, b) => a.unitPriceMinor! >= b.unitPriceMinor! ? a : b,
    );
    final low = best.unitPriceMinor!;
    final high = worst.unitPriceMinor!;
    if (!(low < high) || high == const Fraction(0)) return null;
    final tenths = ((high - low) * const Fraction(1000) / high).roundHalfUp();
    final shown = tenths % 10 == 0 ? tenths ~/ 10 : tenths / 10;
    final text = shown.toString();
    return priceLensStrings(context, 'headline', {
      'best': best.option.label,
      'worst': worst.option.label,
      'pct': persian
          ? nexDigits(text.replaceAll('.', '٫'), persian: true)
          : text,
      'unit': unitWord,
    });
  }

  /// The result as plain lines — one per offer, the cheapest marked — for
  /// pasting into a chat or a note.
  String _shareText(BuildContext context, String unitWord) {
    final s = priceLensStrings;
    final headline = _headline(context, unitWord);
    final lines = [
      s(context, 'resultTitle', {'unit': unitWord}),
      ?headline,
      for (final result in comparison.results)
        if (result.unitPriceMinor case final price?)
          '${result.isBest ? '✓ ' : '• '}${s(context, 'unitPriceOf', {'label': result.option.label, 'price': lensMoney(context, price, result.option.currency), 'unit': unitWord})}'
        else
          '• ${result.option.label} · ${s(context, 'notComparable')}',
    ];
    return lines.join('\n');
  }

  Future<void> _share(BuildContext context, String unitWord) async {
    try {
      await nexModuleShareText(
        [
          _shareText(context, unitWord),
          priceLensStrings(context, 'priceComparisonNote'),
        ].join('\n'),
      );
    } catch (_) {
      if (context.mounted) {
        nexShowBanner(
          context,
          message: priceLensStrings(context, 'shareFailed'),
          kind: NexBannerKind.failed,
        );
      }
    }
  }

  Future<void> _copy(BuildContext context, String unitWord) async {
    final s = priceLensStrings;
    await nexModuleCopyText(_shareText(context, unitWord));
    if (context.mounted) {
      nexShowBanner(context, message: s(context, 'copied'));
    }
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.result,
    required this.best,
    required this.unitWord,
    required this.persian,
  });

  final OptionResult result;
  final Fraction? best;
  final String unitWord;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = priceLensStrings;
    final hue = NexHue.violet.of(theme.brightness);
    final price = result.unitPriceMinor;
    if (price == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
        child: Text(
          '${result.option.label} · ${s(context, 'notComparable')}',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    final bestPrice = best;
    final savings = bestPrice == null ? null : savingsOf(result, bestPrice);
    final label = result.option.label;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (result.isBest)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: NexSpacing.xs),
                  child: Icon(Icons.check_circle_outline, size: 16, color: hue),
                ),
              Expanded(
                child: Text(
                  s(context, 'unitPriceOf', {
                    'label': label,
                    'price': lensMoney(context, price, result.option.currency),
                    'unit': unitWord,
                  }),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (savings != null) ...[
            const SizedBox(height: NexSpacing.xs),
            Text(
              s(context, 'savingsVsBest', {
                'extra': lensMoney(
                  context,
                  savings.perUnit,
                  result.option.currency,
                ),
              }),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Text(
              s(context, 'savingsForQuantity', {
                'price': lensMoney(
                  context,
                  savings.forThisAmount,
                  result.option.currency,
                ),
              }),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
