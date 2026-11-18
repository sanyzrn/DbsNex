import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'comparison.dart';
import 'controller.dart';
import 'lens_pages.dart';
import 'lens_widgets.dart';
import 'option_editor.dart';
import 'options.dart';
import 'price_lens_common.dart';
import 'strings.dart';
import 'units.dart';
import 'rational.dart';
import 'history_status.dart';
import 'privacy.dart';
import 'draft_guard.dart';
import 'choices.dart';
import 'product_pages.dart';
import 'money_render.dart';
part 'screen_actions.dart';
part 'price_lens_calculator.dart';
part 'workspace_draft.dart';

/// The Price Lens: a live calculator by default — nothing is saved
/// until the person chooses to. Two to four offers, one common unit,
/// and the exact answer to "which package is actually cheaper".
class PriceLensScreen extends StatelessWidget {
  const PriceLensScreen({super.key, required this.store});
  final NexModuleStore store;
  @override
  Widget build(BuildContext context) => LensPrivacy(
    child: NexModuleCalendar(
      solar: NexModuleStrings.persian(context),
      child: _LensWorkspace(store: store),
    ),
  );
}

class _LensWorkspace extends StatefulWidget {
  const _LensWorkspace({required this.store});
  final NexModuleStore store;
  @override
  State<_LensWorkspace> createState() => _PriceLensScreenState();
}

class _PriceLensScreenState extends State<_LensWorkspace> {
  late final PriceLensController controller = PriceLensController(widget.store);

  /// The calculator's scratch state — never written to the store
  /// unless the person saves.
  List<PriceOption> options = [];

  /// The common unit the comparison divides by; defaults to the first
  /// offer's family canonical unit.
  String? commonUnitKey;
  bool _writing = false;
  int _tab = 0;
  bool _scratchReady = false, _scratchFailed = false, _scratchReading = false;
  late final _scratch = NexModuleFormDraft(
    widget.store,
    'workspace',
    {'workspace': 1},
    {},
    () => {
      'workspaceVersion': 1,
      'tab': _tab,
      'commonUnit': commonUnitKey,
      'offers': [
        for (final o in options)
          {'id': o.id, 'body': o.valid ? o.toBody() : o.source ?? o.toBody()},
      ],
    },
  );

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
    unawaited(_restoreWorkspace());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scratch.close();
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
      _workspaceChanged();
    });
  }

  Future<void> _editOption({PriceOption? existing}) => showOptionEditor(
    context,
    existing: existing,
    store: widget.store,
    onSave: _upsertOption,
  );

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
    final index = options.indexWhere((o) => o.id == option.id);
    setState(() => options = options.where((o) => o.id != option.id).toList());
    _workspaceChanged();
    nexShowBanner(
      context,
      message: s(context, 'offerRemoved'),
      actionLabel: s(context, 'undo'),
      onAction: () {
        if (mounted &&
            options.every((o) => o.id != option.id) &&
            options.length < 4) {
          setState(
            () => options.insert(index.clamp(0, options.length), option),
          );
          _workspaceChanged();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = priceLensStrings;
    return DraftGuard(
      draft: _scratch,
      busy: () => _writing || !_scratchReady && !_scratchFailed,
      child: Scaffold(
        appBar: NexAppBar(
          title: Text(s(context, 'title')),
          actions: [
            const LensPrivacyButton(),
            IconButton(
              tooltip: s(context, 'resetTooltip'),
              onPressed: _scratchReady && !_scratchFailed ? _reset : null,
              icon: const Icon(Icons.restart_alt),
            ),
            NexPopupMenuButton<String>(
              tooltip: s(context, 'moreActions'),
              onSelected: (action) => unawaited(_menu(action)),
              itemBuilder: (c) => [
                nexMenuItem(
                  value: 'save',
                  icon: Icons.bookmark_add_outlined,
                  label: s(c, 'saveComparison'),
                ),
                nexMenuItem(
                  value: 'memory',
                  icon: Icons.history,
                  label: s(c, 'memoryTitle'),
                ),
                nexMenuItem(
                  value: 'saved',
                  icon: Icons.bookmarks_outlined,
                  label: s(c, 'savedComparisons'),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton:
            _tab == 0 &&
                _scratchReady &&
                !_scratchFailed &&
                options.isNotEmpty &&
                options.length < 4
            ? FloatingActionButton.extended(
                heroTag: null,
                key: const ValueKey('lens-add'),
                onPressed: _writing ? null : () => unawaited(_editOption()),
                icon: const Icon(Icons.add),
                label: Text(s(context, 'addOption')),
              )
            : null,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(NexSpacing.md),
              child: NexAdaptiveSegments<int>(
                segments: [
                  for (final (index, key) in [
                    'compareTab',
                    'productsTab',
                    'shoppingTab',
                  ].indexed)
                    ButtonSegment(value: index, label: Text(s(context, key))),
                ],
                selected: {_tab},
                onSelectionChanged: (v) {
                  setState(() => _tab = v.first);
                  _workspaceChanged();
                },
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  !_scratchReady && !_scratchFailed
                      ? const Center(child: CircularProgressIndicator())
                      : _scratchFailed
                      ? NexEmptyState(
                          icon: Icons.refresh,
                          message: s(context, 'draftReadFailed'),
                          action: TextButton(
                            onPressed: _restoreWorkspace,
                            child: Text(s(context, 'retry')),
                          ),
                        )
                      : _calculator(context),
                  LensProductsPage(
                    controller: controller,
                    onCompare: () => setState(() => _tab = 0),
                  ),
                  LensProductsPage(
                    controller: controller,
                    shopping: true,
                    onCompare: () => setState(() => _tab = 0),
                  ),
                ],
              ),
            ),
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
      LensChoices<String>(
        key: const ValueKey('lens-common-units'),
        values: unitsOfFamily(unit.family).map((u) => u.key).toList(),
        value: unit.key,
        label: (key) => unitWordOf(context, key),
        keyFor: (key) => ValueKey('lens-common-$key'),
        onChanged: (key) {
          setState(() => commonUnitKey = key);
          _workspaceChanged();
        },
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
    final s = priceLensStrings;
    for (final option in options) {
      final match = memoryMatchFor(option, controller.memories);
      if (match == null) continue;
      final difference = memoryDifference(option, match);
      final zero = difference == const Fraction(0),
          negative = difference < const Fraction(0);
      final magnitude = negative ? const Fraction(0) - difference : difference;
      final history = zero
          ? s(context, 'memorySame', {
              'price': lensMoney(context, match.exactPaid, match.currency),
              'date': lensFullDate(context, match.date),
            })
          : s(context, negative ? 'memoryLower' : 'memoryHigher', {
              'diff': lensMoney(context, magnitude, match.currency),
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
