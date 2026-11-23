import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'editor.dart';
import 'irr_unit.dart';
import 'ledger.dart';
import 'model.dart';
import 'presentation.dart';
import 'strings.dart';
import 'valuation.dart';

part 'screen_holdings.dart';
part 'screen_prices.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key, required this.store});
  final NexModuleStore store;
  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen>
    with WidgetsBindingObserver {
  late final ledger = AssetLedger(widget.store);
  final revealed = ValueNotifier(false);
  StreamSubscription<void>? _changes;
  IrrUnit unit = IrrUnit.toman;
  int tab = 0;
  bool ready = false, secureFailed = false, leased = false;
  bool loading = false, loadFailed = false, writing = false;
  AssetMarket selected = AssetMarket.gold;
  AssetType? typeFilter;

  String s(String key, [Fields args = const {}]) =>
      assetStrings(context, key, args);
  bool get fa => NexModuleStrings.persian(context);
  String cash(BigInt rial) => moneyLabel(context, rial, unit);
  String number(BigInt n, int digits) => fixedNumber(n, digits, fa);
  String date(DateTime d) => assetDate(context, d);
  Valuation get valuation => ledger.valuation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A backup restore, an Undo or a write from the quick view can change the
    // book while this screen is open. Reload quietly; the screen's own
    // mutations already reload after they finish.
    _changes = widget.store.changes.listen((_) {
      if (mounted && revealed.value && !writing) unawaited(load());
    });
    unawaited(protect());
  }

  Future<void> protect() async {
    if (leased) return;
    leased = true;
    final ok = await NexSecureWindow.acquirePrivateSurface();
    if (!mounted) return;
    if (!ok) {
      leased = false;
      await NexSecureWindow.releasePrivateSurface();
      if (!mounted) return;
    }
    setState(() {
      ready = ok;
      secureFailed = !ok;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      FocusManager.instance.primaryFocus?.unfocus();
      revealed.value = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    if (leased) unawaited(NexSecureWindow.releasePrivateSurface());
    revealed.dispose();
    super.dispose();
  }

  Future<void> reveal() async {
    if (!ready) return;
    revealed.value = true;
    await load();
  }

  Future<void> load() async {
    if (loading || !mounted) return;
    setState(() {
      loading = true;
      loadFailed = false;
    });
    try {
      await ledger.load();
    } on Object {
      if (mounted) setState(() => loadFailed = true);
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          // A filter whose only asset was sold or deleted must not leave an
          // empty page with no explanation.
          if (typeFilter != null &&
              !ledger.valuation.positions.any(
                (position) => position.holding.market.type == typeFilter,
              )) {
            typeFilter = null;
          }
        });
      }
    }
  }

  Future<void> editor(
    String kind, {
    AssetMarket market = AssetMarket.gold,
    ModuleRecord? original,
  }) async {
    if (writing || !revealed.value) return;
    setState(() => writing = true);
    try {
      await nexShowSheet<void>(
        context: context,
        dismissible: false,
        swipeToClose: true,
        builder: (_) => AssetEditor(
          store: widget.store,
          revealed: revealed,
          kind: kind,
          initialMarket: market,
          initialUnit: unit,
          original: original,
          quotes: [...valuation.history.values.expand((series) => series)],
          save: (id, fields) => ledger.save(kind, id, fields, original),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => writing = false);
        if (revealed.value) await load();
      }
    }
  }

  /// Straight from a lot or a benchmark to the price it needs, instead of
  /// making the person find it again in another tab.
  Future<void> openQuote(AssetMarket market) async {
    if (!revealed.value) return;
    setState(() => selected = market);
    await editor('quote', market: market);
  }

  String deleteBody(ModuleRecord record) => switch (record.kind) {
    'holding' => s('deleteHoldingBody'),
    'quote' => s('deleteQuoteBody'),
    _ => s('deleteGoalBody'),
  };

  Future<void> remove(ModuleRecord record) async {
    if (writing) return;
    final accepted = await nexShowDialog<bool>(
      context: context,
      builder: (c) => NexAlertDialog(
        title: Text(assetStrings(c, 'deleteTitle')),
        content: NexDialogBody(
          child: Text(assetStrings(c, deleteBody(record))),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(assetStrings(c, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
              foregroundColor: Theme.of(c).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text(assetStrings(c, 'delete')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted || !revealed.value || writing) return;
    final deleted = await mutation(() => ledger.remove(record));
    if (!deleted || !mounted) return;
    nexShowBanner(
      context,
      message: s('deleted'),
      actionLabel: s('undo'),
      onAction: () => mutation(() => ledger.restore(record)),
    );
  }

  Future<bool> mutation(Future<void> Function() action) async {
    if (writing || !mounted) return false;
    setState(() => writing = true);
    try {
      await action();
    } on Object {
      if (mounted) {
        nexShowBanner(
          context,
          message: s('saveError'),
          kind: NexBannerKind.failed,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => writing = false);
    }
    if (mounted && revealed.value) await load();
    return true;
  }

  void selectMarket(AssetMarket market, {bool openPrices = false}) {
    setState(() {
      selected = market;
      if (openPrices) tab = 1;
    });
  }

  Widget entryMenu(ModuleRecord record, VoidCallback edit) =>
      NexPopupMenuButton<String>(
        onSelected: (choice) {
          if (!revealed.value) return;
          if (choice == 'edit') {
            edit();
          } else {
            unawaited(remove(record));
          }
        },
        itemBuilder: (_) => [
          nexMenuItem(
            value: 'edit',
            icon: Icons.edit_outlined,
            label: s('edit'),
          ),
          nexMenuItem(
            value: 'delete',
            icon: Icons.delete_outline,
            label: s('delete'),
            destructive: true,
          ),
        ],
      );

  void toggleUnit() => setState(
    () => unit = unit == IrrUnit.toman ? IrrUnit.rial : IrrUnit.toman,
  );

  void setTypeFilter(AssetType? type) => setState(() => typeFilter = type);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: revealed,
    builder: (context, visible, _) => Scaffold(
      appBar: NexAppBar(
        title: Text(s('title')),
        actions: [
          if (visible) ...[
            Tooltip(
              message: s(unit == IrrUnit.toman ? 'showRial' : 'showToman'),
              child: TextButton(
                key: const ValueKey('assets-unit'),
                onPressed: writing ? null : toggleUnit,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.sm,
                  ),
                ),
                child: Text(s(unit.key)),
              ),
            ),
            IconButton(
              key: const ValueKey('assets-hide'),
              tooltip: s('hide'),
              icon: const Icon(Icons.visibility_off_outlined),
              onPressed: () => revealed.value = false,
            ),
          ],
        ],
      ),
      body: SafeArea(child: !visible ? privacy() : workspace()),
    ),
  );

  Widget privacy() => ListView(
    padding: const EdgeInsets.all(NexSpacing.md),
    children: [
      NexModuleHero(
        moduleId: 'assets',
        icon: Icons.lock_outline,
        headline: s('privateTitle'),
        caption: s(
          ready
              ? 'privateHint'
              : secureFailed
              ? 'secureError'
              : 'securing',
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            key: const ValueKey('assets-reveal'),
            onPressed: ready
                ? reveal
                : secureFailed
                ? () {
                    setState(() => secureFailed = false);
                    unawaited(protect());
                  }
                : null,
            icon: ready
                ? const Icon(Icons.visibility_outlined)
                : secureFailed
                ? const Icon(Icons.refresh)
                : const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
            label: Text(
              s(
                ready
                    ? 'reveal'
                    : secureFailed
                    ? 'retry'
                    : 'securingShort',
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget workspace() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (loadFailed) {
      return NexEmptyState(
        icon: Icons.refresh,
        message: s('loadError'),
        action: TextButton(onPressed: load, child: Text(s('retry'))),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(NexSpacing.sm),
          child: NexAdaptiveSegments<int>(
            segments: [
              for (final (i, key) in ['book', 'prices', 'goals'].indexed)
                ButtonSegment(value: i, label: Text(s(key))),
            ],
            selected: {tab},
            onSelectionChanged: writing
                ? null
                : (v) => setState(() => tab = v.single),
          ),
        ),
        Expanded(
          child: AbsorbPointer(
            absorbing: writing,
            child: NexSegmentSwap(
              selection: tab,
              child: ListView(
                key: PageStorageKey(tab),
                padding: const EdgeInsets.all(NexSpacing.md),
                children: [
                  if (ledger.damaged) ...[
                    damagedNotice(),
                    const SizedBox(height: NexSpacing.md),
                  ],
                  ...switch (tab) {
                    0 => holdingsView(),
                    1 => pricesView(),
                    _ => goalsView(),
                  },
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget damagedNotice() => NexPanel(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: NexSpacing.sm),
        Expanded(child: Text(s('damaged'))),
      ],
    ),
  );
}
