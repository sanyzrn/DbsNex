import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_math.dart';
import 'loan_model.dart';
import 'loan_people.dart';
import 'loan_row.dart';
import 'loan_summary_card.dart';
import 'module.dart';
import 'money_format.dart';
import 'record_bundle.dart';
import 'store_state.dart';

/// Every person who has a record, with what is still between you — owed to
/// you and owed by you apart, each in its own currencies.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen>
    with StoreState<PeopleScreen> {
  List<Loan> _loans = const [];
  List<LoanReturn> _returns = const [];
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load() => readRecords(() async {
    await RecordBundle.recover(widget.store);
    final loans = await widget.store.list('loan');
    final returns = await widget.store.list('return');
    if (!mounted) return;
    setState(() {
      _loans = loans.map(Loan.fromRecord).toList();
      _returns = returns.map(LoanReturn.fromRecord).toList();
    });
  });

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final people = peopleOf(_loans, _returns);
    return Scaffold(
      appBar: NexAppBar(title: Text(strings(context, 'people'))),
      body: recordsBody(
        people.isEmpty
            ? NexEmptyState(
                icon: Icons.people_outline,
                message: strings(context, 'peopleEmpty'),
              )
            : ListView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.lg + nexBottomInset(context),
                ),
                children: [
                  for (final (index, person) in people.indexed)
                    NexGroupedRow(
                      index: index,
                      count: people.length,
                      child: _PersonTile(
                        person: person,
                        onTap: () => unawaited(
                          Navigator.push(
                            context,
                            NexPageRoute<void>(
                              builder: (_) => PersonScreen(
                                store: widget.store,
                                personKey: person.key,
                              ),
                            ),
                          ),
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

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person, required this.onTap});

  final PersonLedger person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    String line(LoanSummary s) => [
      for (final t in s.money)
        formatMoney(t.minor, t.currency, t.digits, persian),
      if (s.itemsOut > 0) strings(context, 'itemsOut', {'n': s.itemsOut}),
    ].join(' · ');
    final lines = [
      if (!person.owedToMe.isEmpty)
        strings(context, 'theyOweYou', {'amount': line(person.owedToMe)}),
      if (!person.iOwe.isEmpty)
        strings(context, 'youOweThem', {'amount': line(person.iOwe)}),
      if (!person.open) strings(context, 'allSettled'),
    ];
    return ListTile(
      key: ValueKey('person-${person.key}'),
      onTap: onTap,
      title: Text(
        person.name.isEmpty ? strings(context, 'untitledPerson') : person.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        lines.join('\n'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      isThreeLine: lines.length > 1,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

/// One person's page: both directions, every record.
class PersonScreen extends StatefulWidget {
  const PersonScreen({super.key, required this.store, required this.personKey});

  final NexModuleStore store;
  final String personKey;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen>
    with StoreState<PersonScreen> {
  List<Loan> _loans = const [];
  List<LoanReturn> _returns = const [];
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load() => readRecords(() async {
    final loans = await widget.store.list('loan');
    final returns = await widget.store.list('return');
    if (!mounted) return;
    setState(() {
      _loans = [
        for (final l in loans.map(Loan.fromRecord))
          if (personKey(l.person) == widget.personKey) l,
      ];
      _returns = returns.map(LoanReturn.fromRecord).toList();
    });
  });

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final name = _loans.isEmpty ? '' : _loans.first.person.trim();
    final lent = _loans.where((l) => l.direction == LoanDirection.lent);
    final borrowed = _loans.where((l) => l.direction == LoanDirection.borrowed);
    return Scaffold(
      appBar: NexAppBar(
        title: Text(
          name.isEmpty ? strings(context, 'untitledPerson') : name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: recordsBody(
        ListView(
          padding: EdgeInsetsDirectional.fromSTEB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            NexSpacing.lg + nexBottomInset(context),
          ),
          children: [
            LoanSummaryCard(
              summary: LoanSummary.of(lent, _returns),
              owedToMe: true,
            ),
            const SizedBox(height: NexSpacing.sm),
            LoanSummaryCard(
              summary: LoanSummary.of(borrowed, _returns),
              owedToMe: false,
            ),
            const SizedBox(height: NexSpacing.md),
            for (final (title, group) in [
              (strings(context, 'tabLent'), lent.toList()),
              (strings(context, 'tabBorrowed'), borrowed.toList()),
            ])
              if (group.isNotEmpty) ...[
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: NexSpacing.sm),
                for (final (index, loan) in group.indexed)
                  LoanRow(
                    index: index,
                    count: group.length,
                    loan: loan,
                    standing: LoanMath.standing(loan, _returns),
                    store: widget.store,
                  ),
                const SizedBox(height: NexSpacing.md),
              ],
          ],
        ),
        () => unawaited(_load()),
      ),
    );
  }
}
