import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'privacy.dart';
import 'strings.dart';
import 'values.dart';

class ChequeChoices extends StatelessWidget {
  const ChequeChoices({
    super.key,
    required this.values,
    required this.value,
    required this.onChanged,
    this.prefix = '',
  });
  final List<String> values;
  final String value, prefix;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: NexSpacing.sm,
    runSpacing: NexSpacing.sm,
    children: [
      for (final v in values)
        ChoiceChip(
          label: Text(chequeStrings(context, '$prefix$v')),
          selected: v == value,
          onSelected: onChanged == null ? null : (_) => onChanged!(v),
        ),
    ],
  );
}

String chequeNext(Cheque c) => c.purpose == 'guarantee'
    ? 'actionGuarantee'
    : c.status == 'bounced'
    ? 'actionBounced'
    : c.status == 'deposited'
    ? 'actionDeposited'
    : c.direction == 'outgoing'
    ? 'actionOutgoing'
    : 'actionIncoming';

class ChequeTile extends StatelessWidget {
  const ChequeTile({
    super.key,
    required this.cheque,
    required this.onTap,
    required this.today,
  });
  final Cheque cheque;
  final VoidCallback onTap;
  final DateTime today;
  @override
  Widget build(BuildContext context) {
    final c = cheque, s = chequeStrings, valid = c.valid;
    final day = c.actionDay,
        delta = day == null ? null : chequeDaysBetween(today, day);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: NexPanel(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(NexSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      c.direction == 'outgoing'
                          ? Icons.north_east
                          : Icons.south_west,
                    ),
                    const SizedBox(width: NexSpacing.sm),
                    Expanded(
                      child: NexTextDirection(
                        text: c.party,
                        child: Text(
                          c.party.isEmpty
                              ? s(context, 'unknownParty')
                              : c.party,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NexSpacing.sm),
                if (valid)
                  Text(
                    '${chequeMoney(context, c.remaining, unit: c.unit)} ${s(context, c.unit)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                Text(
                  valid
                      ? '${s(context, c.direction)} · ${s(context, c.purpose)} · ${s(context, 'status_${c.status}')}'
                      : s(context, 'invalid'),
                ),
                if (valid && !c.closed)
                  Text(
                    s(context, 'next', {'action': s(context, chequeNext(c))}),
                  ),
                if (valid && day != null)
                  Text(
                    '${nexModuleDateLabel(context, day)} · ${s(context, delta == 0
                        ? 'today'
                        : delta! < 0
                        ? 'late'
                        : 'days', {'n': delta!.abs()})}',
                  ),
                if (valid && day == null && !c.closed)
                  Text(s(context, 'noDate')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChequeDraftGuard extends StatefulWidget {
  const ChequeDraftGuard({
    super.key,
    required this.draft,
    required this.busy,
    required this.child,
  });
  final NexModuleFormDraft draft;
  final bool Function() busy;
  final Widget child;
  @override
  State<ChequeDraftGuard> createState() => _ChequeDraftGuardState();
}

class _ChequeDraftGuardState extends State<ChequeDraftGuard> {
  bool _leaving = false;
  Future<void> _back() async {
    if (_leaving || widget.busy()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _leaving = true);
    if (!await widget.draft.finish()) {
      widget.draft.resume();
      if (mounted) {
        setState(() => _leaving = false);
        nexShowBanner(
          context,
          message: chequeStrings(context, 'saveError'),
          kind: NexBannerKind.failed,
        );
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: AbsorbPointer(absorbing: _leaving, child: widget.child),
  );
}

String chequeMoney(BuildContext context, BigInt rial, {String unit = 'toman'}) {
  if (chequeHidden(context)) return '••••';
  final ten = BigInt.from(10);
  final whole = unit == 'rial' ? rial : rial ~/ ten;
  final grouped = whole.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final fraction = unit == 'toman' && rial % ten != BigInt.zero
      ? '.${rial % ten}'
      : '';
  return nexDigits(
    '$grouped$fraction',
    persian: NexModuleStrings.persian(context),
  );
}
