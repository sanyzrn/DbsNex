import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'detail.dart';
import 'editor.dart';
import 'model.dart';
import 'strings.dart';

class FamilyFundsScreen extends StatefulWidget {
  const FamilyFundsScreen({super.key, required this.store});
  final NexModuleStore store;
  @override
  State<FamilyFundsScreen> createState() => _FamilyFundsScreenState();
}

class _FamilyFundsScreenState extends State<FamilyFundsScreen> {
  late Future<List<ModuleRecord>> records = widget.store.list('fund');

  Future<void> create() async {
    final today = fundMonth(DateTime.now());
    await openFundEditor(
      context,
      widget.store,
      keyName: 'fund:new',
      title: fundStrings(context, 'new'),
      initial: today,
      fields: ['name', 'shareAmount', 'payDay', 'drawDay', 'rules'],
      validate: (d) =>
          (d['name'] as String).isEmpty ||
              !between(d['shareAmount'], 1, 100000000000) ||
              !between(d['payDay'], 1, 31) ||
              !between(d['drawDay'], 1, 31)
          ? 'invalid'
          : null,
      save: (d) async {
        final id = d['id'] as String;
        if (await widget.store.get('fund', id) == null) {
          await widget.store.put('fund', id, newFundBody(d));
        }
      },
    );
    if (mounted) {
      setState(() {
        records = widget.store.list('fund');
      });
    }
  }

  Future<void> open(Fund f) async {
    await Navigator.of(context).push<void>(
      NexPageRoute(
        builder: (_) => FundDetail(store: widget.store, initial: f),
      ),
    );
    if (mounted) {
      setState(() {
        records = widget.store.list('fund');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = fundStrings;
    return Scaffold(
      appBar: NexAppBar(title: Text(s(context, 'title'))),
      body: SafeArea(
        child: FutureBuilder<List<ModuleRecord>>(
          future: records,
          builder: (context, snap) {
            if (snap.hasError) {
              return NexEmptyState(
                icon: Icons.refresh,
                message: s(context, 'loadError'),
                action: TextButton(
                  onPressed: () => setState(() {
                    records = widget.store.list('fund');
                  }),
                  child: Text(s(context, 'retry')),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final funds = snap.data!.map(Fund.read).nonNulls.toList();
            return ListView(
              padding: const EdgeInsets.all(NexSpacing.md),
              children: [
                NexModuleHero(
                  moduleId: 'family_fund',
                  icon: Icons.groups_outlined,
                  headline: s(context, 'title'),
                  caption: s(context, 'tagline'),
                ),
                const SizedBox(height: NexSpacing.md),
                if (funds.length != snap.data!.length)
                  Text(s(context, 'loadError')),
                if (funds.isEmpty) Text(s(context, 'empty')),
                for (final f in funds)
                  Padding(
                    padding: const EdgeInsets.only(bottom: NexSpacing.sm),
                    child: NexPanel(
                      child: ListTile(
                        title: Text(f.name),
                        subtitle: Text(f.start.title(context)),
                        leading: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                        onTap: () => unawaited(open(f)),
                      ),
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: create,
                    icon: const Icon(Icons.add),
                    label: Text(s(context, 'new')),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

bool between(Object? value, int low, int high) =>
    value is int && value >= low && value <= high;

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
