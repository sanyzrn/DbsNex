part of 'price_lens_screen.dart';

extension _LensCalculator on _PriceLensScreenState {
  Widget _calculator(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = priceLensStrings;
    final persian = NexModuleStrings.persian(context);
    final unit = _commonUnit;
    final comparison = unit == null || options.length < 2
        ? null
        : compareOptions(options, unit);
    final memoryLine = _memoryLine(context);
    return SafeArea(
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
                key: const ValueKey('lens-add'),
                onPressed: _writing ? null : () => unawaited(_editOption()),
                icon: const Icon(Icons.add),
                label: Text(s(context, 'addOption')),
                // Material caps buttons at 40dp tall — a label a 2× text
                // scale cannot fit into; let it grow with the words.
                style: const ButtonStyle(
                  maximumSize: WidgetStatePropertyAll<Size?>(
                    Size(double.infinity, double.infinity),
                  ),
                ),
              ),
            )
          else ...[
            Text(s(context, 'optionsTitle'), style: theme.textTheme.titleSmall),
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
                onEdit: () {
                  if (!_writing) unawaited(_editOption(existing: option));
                },
                onRemember: () {
                  if (!_writing) unawaited(_rememberPrice(option));
                },
                onRemove: () {
                  if (!_writing) unawaited(_removeOption(option));
                },
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
    );
  }
}
