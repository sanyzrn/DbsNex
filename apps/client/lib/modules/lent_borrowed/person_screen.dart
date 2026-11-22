import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_edit_sheet.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'loan_people.dart';
import 'loan_settings.dart';
import 'loan_row.dart';
import 'loan_summary_card.dart';
import 'module.dart';
import 'money_format.dart';
import 'person_message.dart';
import 'store_state.dart';
import 'upgrade_strings.dart';

/// One person's page: both directions, every record.
class PersonScreen extends StatefulWidget {
  const PersonScreen({
    super.key,
    required this.store,
    required this.personKey,
    this.unit,
  });

  final NexModuleStore store;
  final String personKey;
  final IrrUnit? unit;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen>
    with StoreState<PersonScreen> {
  List<Loan> _loans = const [];
  List<LoanReturn> _returns = const [];
  StreamSubscription<void>? _changes;
  late IrrUnit _unit = widget.unit ?? IrrUnit.toman;

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
    final settings = await readLoanSettings(widget.store);
    final loans = await widget.store.list('loan');
    final returns = await widget.store.list('return');
    if (!mounted) return;
    setState(() {
      _unit = settings.irrUnit;
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
    final name = _loans.isEmpty ? '' : _loans.first.person.trim();
    final lent = _loans.where((l) => l.direction == LoanDirection.lent);
    final borrowed = _loans.where((l) => l.direction == LoanDirection.borrowed);
    final owedToMe = LoanSummary.of(lent, _returns);
    final iOwe = LoanSummary.of(borrowed, _returns);
    // One pass for every row on the page, as the list body already does.
    final standings = LoanMath.standingsOf(_loans, _returns);
    return Scaffold(
      appBar: NexAppBar(
        title: Text(
          name.isEmpty ? strings(context, 'untitledPerson') : name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (name.isNotEmpty)
            IconButton(
              key: const ValueKey('person-message'),
              tooltip: upgradeWord(context, 'splitMessage'),
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => unawaited(
                showPersonMessageSheet(
                  context,
                  widget.store,
                  person: name,
                  unit: _unit,
                ),
              ),
            ),
        ],
      ),
      // The other half of a person's page is adding to it: a flatmate's next
      // shared cost, the next thing borrowed, without typing the name again.
      floatingActionButton: _loans.isEmpty || name.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              key: const ValueKey('person-new'),
              onPressed: () => unawaited(
                showLoanEditSheet(
                  context,
                  widget.store,
                  initialDirection: LoanDirection.lent,
                  initialPerson: name,
                  unit: _unit,
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(strings(context, 'newRecord')),
            ),
      body: recordsBody(
        ListView(
          padding: EdgeInsetsDirectional.fromSTEB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            // Clear of the floating button, as on the list.
            NexSpacing.xl * 3 + nexBottomInset(context),
          ),
          children: [
            _PersonLedgerPanel(owedToMe: owedToMe, iOwe: iOwe, unit: _unit),
            const SizedBox(height: NexSpacing.md),
            for (final (icon, title, group) in [
              (
                Icons.north_east_outlined,
                strings(context, 'tabLent'),
                lent.toList(),
              ),
              (
                Icons.south_west_outlined,
                strings(context, 'tabBorrowed'),
                borrowed.toList(),
              ),
            ])
              if (group.isNotEmpty) ...[
                NexShelfHeading(icon: icon, title: title),
                const SizedBox(height: NexSpacing.sm),
                for (final (index, loan) in group.indexed)
                  LoanRow(
                    index: index,
                    count: group.length,
                    loan: loan,
                    standing: standings[loan.id]!,
                    store: widget.store,
                    unit: _unit,
                    showPerson: false,
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

/// One person's standing, both directions, each currency on its own line —
/// the answer to «how do we stand?» before the list of records.
class _PersonLedgerPanel extends StatelessWidget {
  const _PersonLedgerPanel({
    required this.owedToMe,
    required this.iOwe,
    required this.unit,
  });

  final LoanSummary owedToMe;
  final LoanSummary iOwe;
  final IrrUnit unit;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = <(IconData, String, List<String>)>[
      (
        Icons.north_east_outlined,
        strings(context, 'owedToMe'),
        summaryAmountLines(context, owedToMe, unit),
      ),
      (
        Icons.south_west_outlined,
        strings(context, 'iOwe'),
        summaryAmountLines(context, iOwe, unit),
      ),
    ];
    final nothing = owedToMe.isEmpty && iOwe.isEmpty;
    // Where both directions hold the same currency, one line settles the
    // question the page is opened with: how do the two of us stand?
    final net = LoanSummary.net(owedToMe, iOwe);
    final persian = NexModuleStrings.persian(context);
    return NexPanel(
      key: const ValueKey('person-ledger'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (nothing)
            Text(
              strings(context, 'peopleNothingOut'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (final (index, row) in rows.indexed) ...[
              if (row.$3.isNotEmpty) ...[
                if (index > 0) const SizedBox(height: NexSpacing.sm),
                Row(
                  children: [
                    Icon(row.$1, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: NexSpacing.xs),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                for (final line in row.$3)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: NexSpacing.lg,
                      top: NexSpacing.xs,
                    ),
                    child: Text(line, style: theme.textTheme.titleSmall),
                  ),
              ],
            ],
          if (net.isNotEmpty) ...[
            const SizedBox(height: NexSpacing.sm),
            Divider(height: 1, color: scheme.outlineVariant),
            for (final total in net)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: NexSpacing.lg,
                  top: NexSpacing.sm,
                ),
                child: Text(
                  strings(context, total.minor > 0 ? 'netToYou' : 'netToThem', {
                    'amount': formatAmount(
                      total.minor.abs(),
                      total.currency,
                      total.digits,
                      persian,
                      unit,
                    ),
                  }),
                  key: ValueKey('person-net-${total.currency}'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
