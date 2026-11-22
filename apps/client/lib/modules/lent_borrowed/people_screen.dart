import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_model.dart';
import 'loan_people.dart';
import 'loan_settings.dart';
import 'module.dart';
import 'money_format.dart';
import 'person_message.dart';
import 'person_screen.dart';
import 'record_bundle.dart';
import 'store_state.dart';
import 'upgrade_strings.dart';

export 'person_screen.dart';

/// Every person who has a record, with what is still between you — owed to
/// you and owed by you apart, each in its own currencies.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.store, this.unit});

  final NexModuleStore store;
  final IrrUnit? unit;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen>
    with StoreState<PeopleScreen> {
  List<Loan> _loans = const [];
  List<LoanReturn> _returns = const [];
  StreamSubscription<void>? _changes;
  late IrrUnit _unit = widget.unit ?? IrrUnit.toman;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() => readRecords(() async {
    await RecordBundle.recover(widget.store);
    final settings = await readLoanSettings(widget.store);
    final loans = await widget.store.list('loan');
    final returns = await widget.store.list('return');
    if (!mounted) return;
    setState(() {
      _unit = settings.irrUnit;
      _loans = loans.map(Loan.fromRecord).toList();
      _returns = returns.map(LoanReturn.fromRecord).toList();
    });
  });

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final people = peopleOf(_loans, _returns);
    // A ledger with a dozen names is read by finding one of them: the same
    // folding the rest of the module uses, so «سارا» finds «سارا ».
    final needle = personKey(_search.text);
    final shown = needle.isEmpty
        ? people
        : [
            for (final person in people)
              if (personKey(person.name).contains(needle)) person,
          ];
    return Scaffold(
      appBar: NexAppBar(title: Text(strings(context, 'people'))),
      body: recordsBody(
        people.isEmpty
            ? NexEmptyState(
                icon: Icons.people_outline,
                message: strings(context, 'peopleEmpty'),
              )
            : Column(
                children: [
                  if (people.length > 1)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        NexSpacing.md,
                        NexSpacing.sm,
                        NexSpacing.md,
                        0,
                      ),
                      child: NexSearchField(
                        fieldKey: const ValueKey('people-search'),
                        controller: _search,
                        hintText: upgradeWord(context, 'peopleSearch'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  Expanded(
                    child: shown.isEmpty
                        ? NexEmptyState(
                            icon: Icons.search_off_outlined,
                            message: strings(context, 'noMatches'),
                          )
                        : ListView.builder(
                            padding: EdgeInsetsDirectional.fromSTEB(
                              NexSpacing.md,
                              NexSpacing.sm,
                              NexSpacing.md,
                              NexSpacing.lg + nexBottomInset(context),
                            ),
                            itemCount: shown.length,
                            itemBuilder: (context, index) {
                              final person = shown[index];
                              return NexGroupedRow(
                                index: index,
                                count: shown.length,
                                child: _PersonTile(
                                  person: person,
                                  unit: _unit,
                                  onMessage: () => unawaited(
                                    showPersonMessageSheet(
                                      context,
                                      widget.store,
                                      person: person.name,
                                      unit: _unit,
                                    ),
                                  ),
                                  onTap: () => unawaited(
                                    Navigator.push(
                                      context,
                                      NexPageRoute<void>(
                                        builder: (_) => PersonScreen(
                                          store: widget.store,
                                          personKey: person.key,
                                          unit: _unit,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
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
  const _PersonTile({
    required this.person,
    required this.unit,
    required this.onTap,
    required this.onMessage,
  });

  final PersonLedger person;
  final IrrUnit unit;
  final VoidCallback onTap;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = ledgerLines(context, person, unit);
    return ListTile(
      key: ValueKey('person-${person.key}'),
      onTap: onTap,
      contentPadding: const EdgeInsetsDirectional.only(
        start: NexSpacing.md,
        end: NexSpacing.sm,
      ),
      title: Text(
        person.name.isEmpty ? strings(context, 'untitledPerson') : person.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
              child: Text(
                line,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      // The material chevrons mirror themselves, so this points forward in
      // both languages: right in English, left in Persian. Picking the icon
      // by direction as well flipped it twice.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (person.name.isNotEmpty)
            IconButton(
              key: ValueKey('people-message-${person.key}'),
              tooltip: upgradeWord(context, 'splitMessage'),
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: onMessage,
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

/// The lines under a person's name: one per currency, each direction said
/// on its own — «به شما ۵۰٬۰۰۰ تومان بدهکار است» — never one number that
/// mixes the two or the currencies.
List<String> ledgerLines(
  BuildContext context,
  PersonLedger person,
  IrrUnit unit,
) {
  final strings = lentStrings;
  final persian = NexModuleStrings.persian(context);
  // One line per currency, each inside the whole sentence «به شما … بدهکار
  // است» — joining a currency list into one placeholder produced a sentence
  // that broke around the second amount. Items are a count, not a currency,
  // so they get a line of their own.
  List<String> direction(String key, LoanSummary summary) => [
    for (final total in summary.money)
      strings(context, key, {
        'amount': formatAmount(
          total.minor,
          total.currency,
          total.digits,
          persian,
          unit,
        ),
      }),
  ];

  return [
    ...direction('theyOweYou', person.owedToMe),
    if (person.owedToMe.itemsOut > 0)
      strings(
        context,
        person.owedToMe.itemsOut == 1 ? 'itemsOut1' : 'itemsOut',
        {'n': person.owedToMe.itemsOut},
      ),
    ...direction('youOweThem', person.iOwe),
    if (person.iOwe.itemsOut > 0)
      strings(context, person.iOwe.itemsOut == 1 ? 'itemsOut1' : 'itemsOut', {
        'n': person.iOwe.itemsOut,
      }),
    if (!person.open) strings(context, 'allSettled'),
  ];
}
