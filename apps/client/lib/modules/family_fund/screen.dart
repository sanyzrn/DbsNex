import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'detail.dart';
import 'editor.dart';
import 'fund_text.dart';
import 'model.dart';
import 'strings.dart';

class FamilyFundsScreen extends StatefulWidget {
  const FamilyFundsScreen({super.key, required this.store});
  final NexModuleStore store;
  @override
  State<FamilyFundsScreen> createState() => _FamilyFundsScreenState();
}

class _FamilyFundsScreenState extends State<FamilyFundsScreen> {
  List<Fund> funds = const [];
  int unreadable = 0;
  bool loading = true, failed = false;
  int generation = 0;
  StreamSubscription<void>? changes;

  @override
  void initState() {
    super.initState();
    changes = widget.store.changes.listen((_) => unawaited(load()));
    unawaited(load());
  }

  @override
  void dispose() {
    unawaited(changes?.cancel());
    super.dispose();
  }

  Future<void> load({bool spinner = false}) async {
    final ticket = ++generation;
    if (spinner && mounted) {
      setState(() {
        loading = true;
        failed = false;
      });
    }
    try {
      final records = await widget.store.list('fund');
      if (!mounted || ticket != generation) return;
      final read = records.map(Fund.read).nonNulls.toList()
        ..sort((a, b) {
          final byStart = a.start.first.compareTo(b.start.first);
          return byStart != 0 ? byStart : a.name.compareTo(b.name);
        });
      setState(() {
        funds = read;
        unreadable = records.length - read.length;
        loading = false;
        failed = false;
      });
    } on Object {
      if (!mounted || ticket != generation) return;
      setState(() {
        loading = false;
        failed = true;
      });
    }
  }

  Future<void> create() async {
    final today = fundMonth(DateTime.now());
    await openFundEditor(
      context,
      widget.store,
      keyName: 'fund:new',
      title: fundStrings(context, 'new'),
      initial: today,
      fields: ['name', 'shareAmount', 'payDay', 'drawDay', 'rules'],
      validate: (d) {
        if ((d['name'] as String).isEmpty) return 'invalidName';
        if (!between(d['shareAmount'], 1, 100000000000)) {
          return 'invalidShare';
        }
        if (!between(d['payDay'], 1, 31) || !between(d['drawDay'], 1, 31)) {
          return 'invalidDay';
        }
        return null;
      },
      save: (d) async {
        final id = d['id'] as String;
        if (await widget.store.get('fund', id) == null) {
          await widget.store.put('fund', id, newFundBody(d));
        }
      },
    );
    if (mounted) await load();
  }

  Future<void> open(Fund f) async {
    await Navigator.of(context).push<void>(
      NexPageRoute(
        builder: (_) => FundDetail(store: widget.store, initial: f),
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final s = fundStrings;
    return Scaffold(
      appBar: NexAppBar(title: Text(s(context, 'title'))),
      floatingActionButton:
          loading || failed || (funds.isEmpty && unreadable == 0)
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              key: const ValueKey('fund-add'),
              onPressed: create,
              icon: const Icon(Icons.add),
              label: Text(s(context, 'new')),
            ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : failed
            ? NexEmptyState(
                icon: Icons.refresh,
                message: s(context, 'loadError'),
                action: TextButton(
                  onPressed: () => load(spinner: true),
                  child: Text(s(context, 'retry')),
                ),
              )
            : funds.isEmpty && unreadable == 0
            ? NexEmptyState(
                icon: Icons.groups_outlined,
                message: s(context, 'empty'),
                action: FilledButton.icon(
                  key: const ValueKey('fund-add'),
                  onPressed: create,
                  icon: const Icon(Icons.add),
                  label: Text(s(context, 'new')),
                ),
              )
            : _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final s = fundStrings;
    final month = fundMonth(DateTime.now());
    final persian = NexModuleStrings.persian(context);
    var due = 0, paid = 0, members = 0;
    for (final fund in funds) {
      members += fund.members.where((m) => m['until'] == null).length;
      if (month.first.isBefore(fund.start.first)) continue;
      final active = fund.active(month);
      due += active.length;
      paid += active.where((m) => fund.payment(month, m['id']) != null).length;
    }
    final nextStart = funds
        .where((fund) => month.first.isBefore(fund.start.first))
        .map((fund) => fund.start)
        .firstOrNull;
    final headline = due > 0
        ? s(context, 'glancePaidOf', {'paid': paid, 'total': due})
        : nextStart != null
        ? s(context, 'upcoming', {
            'date': nexReadableDate(
              nextStart.first,
              solar: true,
              persian: persian,
            ),
          })
        : s(context, 'glanceNoMembers');
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.xl + NexSpacing.lg,
      ),
      children: [
        if (funds.isNotEmpty)
          NexModuleHero(
            moduleId: 'family_fund',
            icon: Icons.groups_outlined,
            headline: headline,
            caption: s(context, 'tagline'),
            chips: [
              s(context, 'fundsCount', {'n': funds.length}),
              s(context, 'membersCount', {'n': members}),
            ],
            semanticsLabel: '$headline. ${s(context, 'tagline')}',
          ),
        if (unreadable > 0) ...[
          const SizedBox(height: NexSpacing.md),
          NexPanel(
            title: s(context, 'loadError'),
            icon: Icons.error_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s(context, 'unreadable', {'n': unreadable})),
                TextButton(
                  onPressed: () => load(spinner: true),
                  child: Text(s(context, 'retry')),
                ),
              ],
            ),
          ),
        ],
        if (funds.isNotEmpty) const SizedBox(height: NexSpacing.md),
        for (final fund in funds)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.sm),
            child: _FundCard(
              fund: fund,
              month: month,
              onTap: () => unawaited(open(fund)),
            ),
          ),
      ],
    );
  }
}

class _FundCard extends StatelessWidget {
  const _FundCard({
    required this.fund,
    required this.month,
    required this.onTap,
  });
  final Fund fund;
  final NexModuleMonth month;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = fundStrings;
    final started = !month.first.isBefore(fund.start.first);
    final active = started ? fund.active(month) : const <Fields>[];
    final paid = active.where((m) => fund.payment(month, m['id']) != null);
    final winner = fund.winner(month);
    final membership = fund.members.where((m) => m['until'] == null).length;
    final detail = !started
        ? s(context, 'upcoming', {
            'date': nexReadableDate(
              fund.start.first,
              solar: true,
              persian: NexModuleStrings.persian(context),
            ),
          })
        : winner == null
        ? s(context, 'noDraw')
        : s(context, 'winner', {
            'name': nameOf(
              rows(winner['eligible'])
                  .firstWhere((e) => e['id'] == winner['winner']),
            ),
          });
    return NexPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: ValueKey('fund:${fund.id}'),
            onTap: onTap,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.md,
              vertical: NexSpacing.xs,
            ),
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(fund.name),
            isThreeLine: true,
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    s(context, 'membersCount', {'n': membership}),
                    if (started)
                      active.isEmpty
                          ? s(context, 'noActive')
                          : s(context, 'progress', {
                              'paid': paid.length,
                              'total': active.length,
                            }),
                    detail,
                  ].join(fundSep(context)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (started && active.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: NexSpacing.xs,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(NexRadius.xs),
                      child: LinearProgressIndicator(
                        value: paid.length / active.length,
                        minHeight: 4,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

Fields newFundBody(Fields d) => {
  'v': 1,
  'name': d['name'],
  'rules': d['rules'],
  'shareRial': d['shareAmount'],
  'paymentDay': d['payDay'],
  'drawDay': d['drawDay'],
  'start': dayKey((d['month'] as NexModuleMonth).first),
  for (final key in ['members', 'payments', 'draws', 'loans']) key: <Fields>[],
};
