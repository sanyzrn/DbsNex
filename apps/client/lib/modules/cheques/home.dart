import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'detail.dart';
import 'privacy.dart';
import 'plan_model.dart';
import 'plans_page.dart';
import 'month_view.dart';
import 'editor.dart';
import 'logic.dart';
import 'model.dart';
import 'outlook.dart';
import 'repository.dart';
import 'strings.dart';
import 'values.dart';
import 'widgets.dart';

class ChequeHome extends StatefulWidget {
  const ChequeHome({super.key, required this.store});
  final NexModuleStore store;
  @override
  State<ChequeHome> createState() => _ChequeHomeState();
}

class _ChequeHomeState extends State<ChequeHome> with WidgetsBindingObserver {
  late final _repo = ChequeRepository(widget.store);
  final _search = TextEditingController();
  final _scroll = [ScrollController(), ScrollController(), ScrollController()];
  List<Cheque> _rows = [];
  bool _loading = true, _failed = false;
  int _tab = 0, _generation = 0;
  String _direction = 'any', _filter = 'any';
  DateTime? _from, _to;
  StreamSubscription<void>? _changes;
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
    _search.dispose();
    for (final c in _scroll) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final records = await widget.store.list('cheque');
      final plans = await widget.store.list('plan');
      if (mounted && generation == _generation) {
        setState(() {
          _rows = [
            ...records.map((r) => Cheque(r.id, r.body)),
            ...plans.expand((r) => InstalmentPlan(r.id, r.body).cheques()),
          ];
          _loading = false;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _add() => Navigator.of(context).push<void>(
    NexPageRoute(
      builder: (_) => chequePrivateRoute(context, ChequeEditor(repo: _repo)),
    ),
  );
  Future<void> _open(Cheque cheque) => cheque.recordKind == 'plan'
      ? _plans(cheque)
      : Navigator.of(context).push<void>(
          NexPageRoute(
            builder: (_) => chequePrivateRoute(
              context,
              ChequeDetail(repo: _repo, id: cheque.id),
            ),
          ),
        );
  List<Cheque> _filtered(DateTime today) {
    String fold(String v) =>
        chequeDigits(v).toLowerCase().replaceAll('ي', 'ی').replaceAll('ك', 'ک');
    final q = fold(_search.text.trim());
    final identifier = normalizedSayad(q);
    return _rows.where((c) {
      if (_direction != 'any' && c.direction != _direction) return false;
      if (q.isNotEmpty &&
          !['party', 'bank', 'account', 'number', 'sayad', 'note'].any((k) {
            if (k == 'sayad') {
              return identifier.isNotEmpty && c.sayad.contains(identifier);
            }
            return fold(c.text(k)).contains(q);
          })) {
        return false;
      }
      if (_filter == 'needsReview' && c.valid) return false;
      if (_filter == 'openOnly' && (!c.valid || c.closed)) return false;
      if (_filter == 'closedOnly' && (!c.valid || !c.closed)) return false;
      if (_filter == 'overdueOnly' && !chequeOverdue(c, today)) return false;
      if (_from != null &&
          (c.actionDay == null || c.actionDay!.isBefore(_from!))) {
        return false;
      }
      if (_to != null && (c.actionDay == null || c.actionDay!.isAfter(_to!))) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _range(bool from) async {
    final first = from ? DateTime(1900) : _from ?? DateTime(1900),
        last = from ? (_to ?? DateTime(2100, 12, 31)) : DateTime(2100, 12, 31);
    final candidate = (from ? _from : _to) ?? DateTime.now();
    final picked = await nexPickModuleDate(
      context,
      initial: candidate.isBefore(first)
          ? first
          : candidate.isAfter(last)
          ? last
          : candidate,
      first: first,
      last: last,
    );
    if (picked != null && mounted) {
      setState(() {
        if (from) {
          _from = picked;
        } else {
          _to = picked;
        }
      });
    }
  }

  DateTime _month = DateTime.now();
  Future<void> _plans([Cheque? instalment]) => Navigator.of(context).push<void>(
    NexPageRoute(
      builder: (_) => chequePrivateRoute(
        context,
        PlansPage(
          store: widget.store,
          planId: instalment?.recordId,
          instalmentIndex: instalment == null
              ? null
              : int.tryParse(instalment.id.split(':').last),
        ),
      ),
    ),
  );
  void _moveMonth(int delta) {
    final p = nexPersianDate(_month),
        m = p.month - 1 + delta,
        y = p.year + (m / 12).floor(),
        month = (m % 12) + 1;
    setState(() => _month = nexGregorianDate(y, month, 1));
  }

  Widget _all(DateTime today) {
    final s = chequeStrings, rows = _filtered(today);
    return ListView(
      key: const PageStorageKey('cheque-all'),
      controller: _scroll[1],
      padding: EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.xl + nexBottomInset(context) + kMinInteractiveDimension * 2,
      ),
      children: [
        NexSearchField(
          fieldKey: const ValueKey('cheque-search'),
          controller: _search,
          hintText: s(context, 'search'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: NexSpacing.sm),
        ChequeChoices(
          values: const ['any', 'incoming', 'outgoing'],
          value: _direction,
          onChanged: (v) => setState(() => _direction = v),
        ),
        const SizedBox(height: NexSpacing.sm),
        ChequeChoices(
          values: const [
            'any',
            'openOnly',
            'closedOnly',
            'overdueOnly',
            'needsReview',
          ],
          value: _filter,
          onChanged: (v) => setState(() => _filter = v),
        ),
        Wrap(
          spacing: NexSpacing.sm,
          children: [
            TextButton(
              onPressed: () => _range(true),
              child: Text(
                '${s(context, 'from')}: ${_from == null ? s(context, 'any') : nexModuleDateLabel(context, _from!)}',
              ),
            ),
            TextButton(
              onPressed: () => _range(false),
              child: Text(
                '${s(context, 'to')}: ${_to == null ? s(context, 'any') : nexModuleDateLabel(context, _to!)}',
              ),
            ),
            if (_from != null || _to != null)
              TextButton(
                onPressed: () => setState(() {
                  _from = null;
                  _to = null;
                }),
                child: Text(s(context, 'clearRange')),
              ),
          ],
        ),
        const SizedBox(height: NexSpacing.md),
        if (rows.isEmpty) Text(s(context, 'noResults')),
        for (final c in rows)
          ChequeTile(cheque: c, today: today, onTap: () => _open(c)),
      ],
    );
  }

  Widget _follow(DateTime today) {
    final s = chequeStrings,
        rows = actionableCheques(_rows),
        invalid = _rows.where((c) => !c.valid).toList();
    final urgent = <Cheque>[], sayad = <Cheque>[], upcoming = <Cheque>[];
    for (final c in rows) {
      if (chequeOverdue(c, today) || c.status == 'bounced') {
        urgent.add(c);
      } else if (c.text('sayadState') == 'todo') {
        sayad.add(c);
      } else {
        upcoming.add(c);
      }
    }
    return ListView(
      key: const PageStorageKey('cheque-follow'),
      controller: _scroll[0],
      padding: EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.xl + nexBottomInset(context) + kMinInteractiveDimension * 2,
      ),
      children: [
        if (rows.isNotEmpty) ...[
          NexModuleHero(
            moduleId: 'cheques',
            icon: Icons.receipt_long_outlined,
            headline: s(context, 'followCount', {'n': rows.length}),
            caption: s(context, 'followHint'),
          ),
          const SizedBox(height: NexSpacing.md),
        ],
        if (rows.isEmpty && invalid.isEmpty) Text(s(context, 'noResults')),
        for (final (items, title, icon) in [
          (urgent, 'urgent', Icons.warning_amber_outlined),
          (sayad, 'sayadPending', Icons.fact_check_outlined),
          (upcoming, 'upcoming', Icons.event_outlined),
          (invalid, 'needsReview', Icons.error_outline),
        ])
          if (items.isNotEmpty) ...[
            NexShelfHeading(icon: icon, title: s(context, title)),
            for (final c in items)
              ChequeTile(cheque: c, today: today, onTap: () => _open(c)),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = chequeStrings,
        now = DateTime.now(),
        today = DateTime(now.year, now.month, now.day);
    return Scaffold(
      appBar: NexAppBar(
        title: Text(s(context, 'title')),
        actions: [
          const ChequePrivacyButton(),
          IconButton(
            tooltip: s(context, 'plans'),
            onPressed: _plans,
            icon: const Icon(Icons.view_list_outlined),
          ),
        ],
      ),
      floatingActionButton: _loading || _failed || _rows.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              key: const ValueKey('cheque-add'),
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: Text(s(context, 'add')),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? NexEmptyState(
              icon: Icons.refresh,
              message: s(context, 'readError'),
              action: TextButton(
                onPressed: _load,
                child: Text(s(context, 'retry')),
              ),
            )
          : _rows.isEmpty
          ? NexEmptyState(
              icon: Icons.receipt_long_outlined,
              message: s(context, 'empty'),
              action: FilledButton.icon(
                key: const ValueKey('cheque-add'),
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text(s(context, 'add')),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.md,
                  ),
                  child: NexAdaptiveSegments<int>(
                    segments: [
                      for (final (index, key) in [
                        'follow',
                        'all',
                        'outlook',
                        'month',
                      ].indexed)
                        ButtonSegment(
                          value: index,
                          label: Text(s(context, key)),
                        ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (v) => setState(() => _tab = v.first),
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _follow(today),
                      _all(today),
                      ChequeOutlook(
                        rows: _rows,
                        today: today,
                        controller: _scroll[2],
                        open: _open,
                      ),
                      ChequeMonth(
                        rows: _rows,
                        month: _month,
                        move: _moveMonth,
                        open: _open,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
