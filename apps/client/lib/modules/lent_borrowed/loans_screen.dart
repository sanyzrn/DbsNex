import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'cards_screen.dart';
import 'irr_unit.dart';
import 'loan_edit_sheet.dart';
import 'loan_filter.dart';
import 'loan_model.dart';
import 'loan_settings.dart';
import 'loans_screen_body.dart';
import 'module.dart';
import 'people_screen.dart';
import 'splits_screen.dart';
import 'record_bundle.dart';
import 'store_state.dart';
import 'upgrade_strings.dart';

/// The overview: Lent and Borrowed never mix, outstanding comes before
/// settled, and a due date that has passed is said plainly, at the top,
/// where the person is looking when they open the module.
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        StoreState<LoansScreen> {
  List<Loan> _loans = const [];
  List<LoanReturn> _returns = const [];
  StreamSubscription<void>? _changes;
  int _loadToken = 0;
  bool _editorOpen = false;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  /// How an Iranian amount is said: toman until the person chooses rial.
  IrrUnit _unit = IrrUnit.toman;

  /// How far the first tab was pulled past its start edge in this drag.
  double _edgePull = 0;
  final TextEditingController _search = TextEditingController();
  LoanFilter _filter = LoanFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() => readRecords(_read);

  /// One editor at a time: a double-tap on New must not stack two sheets
  /// that each write their own record.
  Future<void> _openEditor(LoanDirection direction) async {
    if (_editorOpen) return;
    _editorOpen = true;
    try {
      await showLoanEditSheet(
        context,
        widget.store,
        initialDirection: direction,
        unit: _unit,
      );
    } finally {
      _editorOpen = false;
    }
  }

  Future<void> _read() async {
    await RecordBundle.recover(widget.store);
    final token = ++_loadToken;
    final settings = await readLoanSettings(widget.store);
    final loans = await widget.store.list('loan');
    final returns = await widget.store.list('return');
    if (!mounted || token != _loadToken) return;
    setState(() {
      _loans = loans.map(Loan.fromRecord).toList();
      _returns = returns.map(LoanReturn.fromRecord).toList();
      _unit = settings.irrUnit;
    });
  }

  /// The unit is how amounts are *said*, so changing it never touches a
  /// record: it is one small preference, saved and read back like a record.
  Future<void> _setUnit(IrrUnit unit) async {
    if (unit == _unit) return;
    final saved = await storeWrite(
      context,
      () => saveIrrUnit(widget.store, unit),
    );
    if (!mounted) return;
    if (saved) setState(() => _unit = unit);
  }

  Future<void> _onMenu(_MenuAction action) async {
    switch (action) {
      case _MenuAction.toman:
        await _setUnit(IrrUnit.toman);
      case _MenuAction.rial:
        await _setUnit(IrrUnit.rial);
      case _MenuAction.splits:
        if (!mounted) return;
        await Navigator.push(
          context,
          NexPageRoute<void>(
            builder: (_) => SplitsScreen(store: widget.store, unit: _unit),
          ),
        );
      case _MenuAction.cards:
        if (!mounted) return;
        await Navigator.push(
          context,
          NexPageRoute<void>(builder: (_) => CardsScreen(store: widget.store)),
        );
    }
  }

  Widget _searchBar(BuildContext context) {
    final strings = lentStrings;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexSearchField(
            fieldKey: const ValueKey('loans-search'),
            controller: _search,
            hintText: strings(context, 'searchHint'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.xs,
            children: [
              for (final filter in LoanFilter.values)
                ChoiceChip(
                  key: ValueKey('loans-filter-${filter.name}'),
                  label: Text(strings(context, 'filter_${filter.name}')),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The tabs swallow a horizontal drag, so the page's own swipe-back never
  /// sees one that starts on the first tab. A drag that is pulled past the
  /// first tab's start edge is the person asking to go back: the second tab
  /// swipes to the first, and the next swipe leaves.
  bool _onTabScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is OverscrollNotification && n.dragDetails != null) {
      if (n.overscroll < 0) _edgePull += -n.overscroll;
    } else if (n is ScrollUpdateNotification &&
        n.dragDetails != null &&
        n.metrics.pixels < n.metrics.minScrollExtent) {
      _edgePull = n.metrics.minScrollExtent - n.metrics.pixels;
    } else if (n is ScrollEndNotification) {
      final pulled = _edgePull;
      _edgePull = 0;
      final route = ModalRoute.of(context);
      if (pulled > 48 &&
          _tabs.index == 0 &&
          (route?.isCurrent ?? false) &&
          !Navigator.of(context).userGestureInProgress) {
        unawaited(Navigator.of(context).maybePop());
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    return Scaffold(
      appBar: NexAppBar(
        title: Text(strings(context, 'title')),
        actions: [
          IconButton(
            key: const ValueKey('loans-people'),
            tooltip: strings(context, 'people'),
            icon: const Icon(Icons.people_outline),
            onPressed: () => unawaited(
              Navigator.push(
                context,
                NexPageRoute<void>(
                  builder: (_) =>
                      PeopleScreen(store: widget.store, unit: _unit),
                ),
              ),
            ),
          ),
          NexPopupMenuButton<_MenuAction>(
            key: const ValueKey('loans-units'),
            tooltip: strings(context, 'unitLabel'),
            icon: const Icon(Icons.tune),
            onSelected: (value) => unawaited(_onMenu(value)),
            itemBuilder: (context) => [
              // A menu that chooses a value: no icons, per the design
              // language's menu rules.
              nexMenuItem(
                value: _MenuAction.toman,
                label: strings(context, 'unitToman'),
              ),
              nexMenuItem(
                value: _MenuAction.rial,
                label: strings(context, 'unitRial'),
              ),
              nexMenuItem(
                value: _MenuAction.splits,
                label: upgradeWord(context, 'splitsTitle'),
              ),
              nexMenuItem(
                value: _MenuAction.cards,
                label: upgradeWord(context, 'cardsTitle'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          key: const ValueKey('loans-tabs'),
          controller: _tabs,
          tabs: [
            Tab(
              key: const ValueKey('loans-tab-lent'),
              text: strings(context, 'tabLent'),
            ),
            Tab(
              key: const ValueKey('loans-tab-borrowed'),
              text: strings(context, 'tabBorrowed'),
            ),
          ],
        ),
      ),
      // One primary action per page: with no record at all it is the button
      // in the empty state, not a second one floating beside it.
      floatingActionButton: _loans.isEmpty
          ? null
          : FloatingActionButton.extended(
              // No hero: a page's button never flies into another's (2.8.2).
              heroTag: null,
              key: const ValueKey('loans-new'),
              onPressed: () => unawaited(
                _openEditor(
                  _tabs.index == 0
                      ? LoanDirection.lent
                      : LoanDirection.borrowed,
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(strings(context, 'newRecord')),
            ),
      body: recordsBody(
        Column(
          children: [
            if (_loans.isNotEmpty) _searchBar(context),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onTabScroll,
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    // Each tab comes back where it was left, not at its top
                    // (2.8.2).
                    LoanListBody(
                      key: const PageStorageKey('loans-lent'),
                      direction: LoanDirection.lent,
                      loans: _loans,
                      returns: _returns,
                      store: widget.store,
                      query: _search.text,
                      filter: _filter,
                      unit: _unit,
                      onNewRecord: () =>
                          unawaited(_openEditor(LoanDirection.lent)),
                    ),
                    LoanListBody(
                      key: const PageStorageKey('loans-borrowed'),
                      direction: LoanDirection.borrowed,
                      loans: _loans,
                      returns: _returns,
                      store: widget.store,
                      query: _search.text,
                      filter: _filter,
                      unit: _unit,
                      onNewRecord: () =>
                          unawaited(_openEditor(LoanDirection.borrowed)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        () => unawaited(_load()),
      ),
    );
  }
}

/// What the list's menu offers: the reading unit, and the two pages that
/// belong to the module but not to the loan list itself.
enum _MenuAction { toman, rial, splits, cards }
