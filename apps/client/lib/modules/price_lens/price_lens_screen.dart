import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'comparison.dart';
import 'controller.dart';
import 'lens_pages.dart';
import 'lens_widgets.dart';
import 'money.dart';
import 'option_editor.dart';
import 'options.dart';
import 'price_lens_common.dart';
import 'strings.dart';
import 'units.dart';
import 'rational.dart';
import 'history_status.dart';
part 'screen_actions.dart';

/// The Price Lens: a live calculator by default — nothing is saved
/// until the person chooses to. Two to four offers, one common unit,
/// and the exact answer to "which package is actually cheaper".
class PriceLensScreen extends StatefulWidget {
  const PriceLensScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<PriceLensScreen> createState() => _PriceLensScreenState();
}

class _PriceLensScreenState extends State<PriceLensScreen> {
  late final PriceLensController controller = PriceLensController(widget.store);

  /// The calculator's scratch state — never written to the store
  /// unless the person saves.
  List<PriceOption> options = [];

  /// The common unit the comparison divides by; defaults to the first
  /// offer's family canonical unit.
  String? commonUnitKey;
  bool _writing = false;
  String? _pendingComparisonId;
  final _pendingMemoryIds = <String, String>{};
  void _paint(VoidCallback action) {
    if (mounted) setState(action);
  }

  @override
  void initState() {
    super.initState();
    unawaited(controller.load());
    controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    controller.dispose();
    super.dispose();
  }

  PriceUnit? get _commonUnit {
    final key = commonUnitKey;
    if (key != null) return priceUnitOf(key);
    // Default: the canonical unit of the first offer's family.
    if (options.isNotEmpty) {
      return canonicalUnitOf(
        (options.first.unit ?? priceUnitOf('piece')!).family,
      );
    }
    return null;
  }

  void _upsertOption(PriceOption option) {
    setState(() {
      final index = options.indexWhere((o) => o.id == option.id);
      if (index >= 0) {
        options[index] = option;
      } else if (options.length < 4) {
        options = [...options, option];
      }
      // A family change moves the common unit along with it.
      final family = (option.unit ?? priceUnitOf('piece')!).family;
      final unit = _commonUnit;
      if (unit == null || unit.family != family) {
        commonUnitKey = canonicalUnitOf(family).key;
      }
    });
  }

  Future<void> _editOption({PriceOption? existing}) =>
      showOptionEditor(context, existing: existing, onSave: _upsertOption);

  Future<void> _removeOption(PriceOption option) async {
    final s = priceLensStrings;
    final answer = await nexShowDialog<String>(
      context: context,
      builder: (dialogContext) => NexAlertDialog(
        title: Text(s(dialogContext, 'removeOptionTitle')),
        content: NexDialogBody(
          child: Text(s(dialogContext, 'removeOptionBody')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s(dialogContext, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'remove'),
            child: Text(s(dialogContext, 'remove')),
          ),
        ],
      ),
    );
    if (answer != 'remove' || !mounted) return;
    setState(() => options = options.where((o) => o.id != option.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = priceLensStrings;
    final persian = NexModuleStrings.persian(context);
    final unit = _commonUnit;
    final comparison = unit == null || options.length < 2
        ? null
        : compareOptions(options, unit);
    final memoryLine = _memoryLine(context);
    return Scaffold(
      appBar: NexAppBar(
        title: Text(s(context, 'title')),
        actions: [
          IconButton(
            tooltip: s(context, 'resetTooltip'),
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
          ),
          NexPopupMenuButton<String>(
            tooltip: s(context, 'moreActions'),
            onSelected: (action) => unawaited(_menu(action)),
            itemBuilder: (menuContext) => [
              PopupMenuItem(
                value: 'save',
                child: Text(s(menuContext, 'saveComparison')),
              ),
              PopupMenuItem(
                value: 'memory',
                child: Text(s(menuContext, 'memoryTitle')),
              ),
              PopupMenuItem(
                value: 'saved',
                child: Text(s(menuContext, 'savedComparisons')),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: options.length < 4
          ? FloatingActionButton.extended(
              key: const ValueKey('lens-add'),
              onPressed: () => unawaited(_editOption()),
              icon: const Icon(Icons.add),
              label: Text(s(context, 'addOption')),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            NexSpacing.xl * 4,
          ),
          children: [
            if (_writing)
              Text(s(context, 'working'), style: theme.textTheme.bodySmall),
            if (controller.readFailed) LensReadError(controller: controller),
            Text(
              s(context, 'noMarketRates'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            if (options.isEmpty)
              NexEmptyState(
                icon: Icons.calculate_outlined,
                message: s(context, 'tooFew'),
                action: FilledButton.icon(
                  onPressed: () => unawaited(_editOption()),
                  icon: const Icon(Icons.add),
                  label: Text(s(context, 'addOption')),
                ),
              )
            else ...[
              Text(
                s(context, 'optionsTitle'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: NexSpacing.xs),
              for (final option in options)
                LensOptionCard(
                  commonUnitKey: unit?.key,
                  key: ValueKey('lens-option-${option.id}'),
                  option: option,
                  result: comparison?.results.firstWhere(
                    (r) => r.option.id == option.id,
                    orElse: () => OptionResult(
                      option: option,
                      unitPriceMinor: null,
                      quantityInCommon: null,
                    ),
                  ),
                  persian: persian,
                  onEdit: () => unawaited(_editOption(existing: option)),
                  onRemember: () {
                    if (!_writing) unawaited(_rememberPrice(option));
                  },
                  onRemove: () => unawaited(_removeOption(option)),
                ),
              if (options.length >= 4)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: NexSpacing.md,
                  ),
                  child: Text(
                    s(context, 'optionLimit'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: NexSpacing.md),
              if (unit != null) ..._unitPicker(context, unit),
              const SizedBox(height: NexSpacing.md),
              if (comparison != null)
                LensResultPanel(
                  comparison: comparison,
                  commonUnit: unit!,
                  persian: persian,
                  memoryLine: memoryLine,
                ),
              if (comparison != null) ...[
                const SizedBox(height: NexSpacing.sm),
                Text(
                  s(context, 'discountNote'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _unitPicker(BuildContext context, PriceUnit unit) {
    final theme = Theme.of(context);
    final s = priceLensStrings;
    return [
      Text(s(context, 'commonUnitLabel'), style: theme.textTheme.titleSmall),
      const SizedBox(height: NexSpacing.xs),
      Wrap(
        key: const ValueKey('lens-common-units'),
        spacing: NexSpacing.sm,
        runSpacing: NexSpacing.xs,
        children: [
          for (final candidate in unitsOfFamily(unit.family))
            LensPill(
              key: ValueKey('lens-common-${candidate.key}'),
              label: unitWordOf(context, candidate.key),
              selected: candidate.key == unit.key,
              onTap: () => setState(() => commonUnitKey = candidate.key),
            ),
        ],
      ),
      const SizedBox(height: NexSpacing.xs),
      Text(
        s(context, 'familyHint'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  /// The line that says what the person entered before, when an offer
  /// exactly matches a memory: a mathematical difference, dated.
  Widget? _memoryLine(BuildContext context) {
    final s = priceLensStrings, fa = NexModuleStrings.persian(context);
    for (final option in options) {
      final match = memoryMatchFor(option, controller.memories);
      if (match == null) continue;
      final exponent = priceExponentOf(match.currency),
          difference = memoryDifference(option, match);
      final zero = difference == const Fraction(0),
          negative = difference < const Fraction(0);
      final magnitude = negative ? const Fraction(0) - difference : difference;
      final history = zero
          ? s(context, 'memorySame', {
              'price':
                  '${formatMinorFraction(match.exactPaid, exponent, persian: fa)} ${match.currency}',
              'date': lensFullDate(context, match.date),
            })
          : s(context, negative ? 'memoryLower' : 'memoryHigher', {
              'diff':
                  '${formatMinorFraction(magnitude, exponent, persian: fa)} ${match.currency}',
              'date': lensFullDate(context, match.date),
            });
      return Text(
        s(context, 'memoryOffer', {'label': option.label, 'history': history}),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return null;
  }
}
