part of 'setup_sheet.dart';

class _SetupSheetState extends _SetupLogic {
  @override
  Widget build(BuildContext context) {
    if (!_restoring && !_loadFailed) _draft.changed();
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DraftGuard(
      draft: _draft,
      busy: () => _saving || _restoring,
      child: _loadFailed
          ? NexEmptyState(
              icon: Icons.refresh,
              message: strings(context, 'draftReadFailed'),
              action: TextButton(
                onPressed: () {
                  setState(() => _restoring = true);
                  unawaited(_restoreDraft());
                },
                child: Text(strings(context, 'retry')),
              ),
            )
          : AbsorbPointer(
              absorbing: _restoring || _saving,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: NexSpacing.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: NexSpacing.md),
                      Text(
                        strings(
                          context,
                          _editing
                              ? 'setupEditTitle'
                              : widget.choose
                              ? 'chooseHabit'
                              : 'setupTitle',
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      if (widget.choose) ...[
                        Wrap(
                          spacing: NexSpacing.sm,
                          runSpacing: NexSpacing.xs,
                          children: [
                            for (final preset in quitPresets)
                              ChoiceChip(
                                key: ValueKey('quit-preset-${preset.key}'),
                                avatar: Icon(preset.icon, size: 18),
                                label: Text(
                                  strings(context, 'habit_${preset.key}'),
                                ),
                                selected: _habit == preset.key,
                                onSelected: _saving
                                    ? null
                                    : (_) => setState(() {
                                        _habit = preset.key;
                                        _perDay.text = '${preset.perDay}';
                                        _perPack.text = preset.packs
                                            ? '20'
                                            : '1';
                                        _minutes.text =
                                            '${preset.minutesPerUnit}';
                                      }),
                              ),
                          ],
                        ),
                        const SizedBox(height: NexSpacing.md),
                      ],
                      if (_habit == 'custom') ...[
                        NexAutoDirection(
                          controller: _name,
                          builder: (context, direction) => TextField(
                            key: const ValueKey('quit-field-name'),
                            controller: _name,
                            textDirection: direction,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              labelText: strings(context, 'customName'),
                              hintText: strings(context, 'customNameHint'),
                              errorText: _nameError,
                            ),
                          ),
                        ),
                        const SizedBox(height: NexSpacing.md),
                      ],
                      if (_preset.safety) ...[
                        NexPanel(
                          key: const ValueKey('quit-safety'),
                          icon: Icons.health_and_safety_outlined,
                          child: Text(
                            strings(context, 'safetyNote'),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: NexSpacing.md),
                      ],
                      if (_details) ...[
                        Text(
                          strings(context, 'explainBaseline'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: NexSpacing.md),
                      ],
                      NexAdaptiveSegments<bool>(
                        key: const ValueKey('quit-start-mode'),
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(strings(context, 'startedAlready')),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text(strings(context, 'startsLater')),
                          ),
                        ],
                        selected: {_later},
                        onSelectionChanged: (s) => setState(() {
                          _later = s.first;
                          _daysAgo.text = _later ? '1' : '0';
                        }),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      _NumberField(
                        key: const ValueKey('smoke-field-days'),
                        controller: _daysAgo,
                        label: strings(
                          context,
                          _later ? 'startsInDaysLabel' : 'daysAgoLabel',
                        ),
                        hint: _later ? null : strings(context, 'daysAgoHint'),
                        errorText: _daysError,
                      ),
                      const SizedBox(height: NexSpacing.md),
                      NexMoreDetails(
                        toggleKey: const ValueKey('quit-details-toggle'),
                        open: _details,
                        onChanged: (open) => setState(() => _details = open),
                        title: strings(context, 'addDetails'),
                        hint: strings(context, 'addDetailsHint'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _NumberField(
                              key: const ValueKey('smoke-field-perday'),
                              controller: _perDay,
                              label: _preset.packs
                                  ? strings(context, 'perDayLabel')
                                  : strings(context, 'perDayUnitsLabel', {
                                      'unit': _unit(context),
                                    }),
                              errorText: _perDayError,
                            ),
                            const SizedBox(height: NexSpacing.md),
                            CurrencyField(
                              key: const ValueKey('smoke-field-currency'),
                              value: _currency,
                              onChanged: _saving
                                  ? null
                                  : (code) => setState(() {
                                      _currency = code;
                                      _digits = moneyDigits(code);
                                      _price.clear();
                                    }),
                            ),
                            const SizedBox(height: NexSpacing.md),
                            _NumberField(
                              decimal: _digits > 0,
                              suffix: _currency,
                              key: const ValueKey('smoke-field-price'),
                              controller: _price,
                              label: strings(
                                context,
                                _preset.packs ? 'priceLabel' : 'unitPriceLabel',
                              ),
                              errorText: _priceError,
                              hint: strings(context, 'amountHint', {
                                'example': localDigits(
                                  moneyInput(12345, _digits),
                                  NexModuleStrings.persian(context),
                                ),
                              }),
                            ),
                            if (_preset.packs) ...[
                              const SizedBox(height: NexSpacing.md),
                              _NumberField(
                                key: const ValueKey('smoke-field-perpack'),
                                controller: _perPack,
                                label: strings(context, 'perPackLabel'),
                                errorText: _perPackError,
                              ),
                            ],
                            const SizedBox(height: NexSpacing.md),
                            _NumberField(
                              key: const ValueKey('quit-field-minutes'),
                              controller: _minutes,
                              label: strings(context, 'minutesLabel'),
                            ),
                            const SizedBox(height: NexSpacing.md),
                            _NumberField(
                              key: const ValueKey('quit-field-goal'),
                              decimal: _digits > 0,
                              suffix: _currency,
                              controller: _goal,
                              label: strings(context, 'goalLabel'),
                              errorText: _goalError,
                            ),
                            const SizedBox(height: NexSpacing.md),
                            NexTextField(
                              key: const ValueKey('quit-field-why'),
                              controller: _why,
                              minLines: 2,
                              maxLines: 4,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                labelText: strings(context, 'whyLabel'),
                                hintText: strings(context, 'whyHint'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: NexSpacing.lg),
                      FilledButton(
                        key: const ValueKey('smoke-save'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: _saving ? null : () => _save(),
                        child: _saving
                            ? const NexInlineSpinner(size: 20)
                            : Text(
                                strings(
                                  context,
                                  _editing ? 'setupEditTitle' : 'startAttempt',
                                ),
                              ),
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () async {
                                await _draft.clear();
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                        child: Text(l10n.cancel),
                      ),
                      const SizedBox(height: NexSpacing.md),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// A whole-number field: left-to-right digits, no symbols, a plain
/// keyboard. The number a person writes here is an amount or a count —
/// never prose.
class _NumberField extends StatelessWidget {
  const _NumberField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.errorText,
    this.decimal = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? errorText;
  final bool decimal;
  final String? suffix;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    textDirection: TextDirection.ltr,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      suffixText: suffix,
    ),
  );
}
