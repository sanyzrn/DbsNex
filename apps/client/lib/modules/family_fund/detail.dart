import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'editor.dart';
import 'fund_text.dart';
import 'irr_unit.dart';
import 'model.dart';
import 'money_format.dart';
import 'reminder.dart';
import 'strings.dart';

part 'detail_actions.dart';
part 'detail_draw.dart';
part 'detail_member.dart';
part 'detail_report.dart';
part 'detail_views.dart';

class FundDetail extends StatefulWidget {
  const FundDetail({super.key, required this.store, required this.initial});
  final NexModuleStore store;
  final Fund initial;
  @override
  State<FundDetail> createState() => _FundDetailState();
}

class _FundDetailState extends State<FundDetail> {
  late Fund fund = widget.initial;
  late DateTime now = DateTime.now();
  late NexModuleMonth month = initialMonth;
  NexModuleMonth get initialMonth =>
      fund.start.first.isAfter(now) ? fund.start : fundMonth(now);
  int tab = 0;
  bool hidden = false, busy = false;
  IrrUnit unit = IrrUnit.toman;
  final scroll = ScrollController();
  final expandedLoans = <String>{};
  String s(String key, [Fields args = const {}]) =>
      fundStrings(context, key, args);
  String date(DateTime value) => nexReadableDate(
    value,
    solar: true,
    persian: NexModuleStrings.persian(context),
  );
  String cash(int value) => hidden
      ? s('masked')
      : formatAmount(value, 'IRR', 0, NexModuleStrings.persian(context), unit);
  bool get future => month.first.isAfter(now);
  bool get started => !month.first.isBefore(fund.start.first);
  int get monthShare => fund.shareFor(month);
  Fields? get winner => fund.winner(month);
  String winnerName(Fields draw) {
    final found = rows(draw['eligible'])
        .where((e) => e['id'] == draw['winner'])
        .firstOrNull;
    return found == null ? s('none') : nameOf(found);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void paint(VoidCallback action) {
    if (mounted) setState(action);
  }

  Future<void> write(Fields next) async {
    if (busy || !mounted) throw StateError('Busy');
    paint(() => busy = true);
    try {
      final old = await widget.store.get('fund', fund.id);
      if (jsonEncode(old) != jsonEncode(fund.body)) {
        throw StateError('Fund changed');
      }
      try {
        await widget.store.put('fund', fund.id, next);
      } on Object {
        // An acknowledgement may fail after the row was written.
        final saved = await widget.store.get('fund', fund.id);
        if (jsonEncode(saved) != jsonEncode(next)) rethrow;
      }
      paint(() {
        fund = Fund(fund.id, next);
        now = DateTime.now();
      });
    } finally {
      paint(() => busy = false);
    }
  }

  Future<void> update(Fields next, {bool undo = false, String? message}) async {
    final before = fund.body;
    try {
      await write(next);
      if (!mounted) return;
      if (undo || message != null) {
        nexShowBanner(
          context,
          message: message ?? s('updated'),
          actionLabel: undo ? s('undo') : null,
          onAction: undo
              ? () async {
                  if (!mounted) return;
                  if (!identical(fund.body, next)) {
                    nexShowBanner(context, message: s('undoFailed'));
                    return;
                  }
                  await update(before);
                }
              : null,
        );
      }
    } on Object {
      if (mounted) {
        nexShowBanner(
          context,
          message: s('saveError'),
          kind: NexBannerKind.failed,
        );
      }
    }
  }

  void changeMonth(NexModuleMonth next) => paint(() {
    month = next;
    now = DateTime.now();
  });

  @override
  Widget build(BuildContext context) => NexModuleCalendar(
    solar: true,
    child: Scaffold(
      appBar: NexAppBar(
        title: Text(fund.name),
        actions: [
          IconButton(
            tooltip: s(hidden ? 'show' : 'hide'),
            onPressed: () => paint(() => hidden = !hidden),
            icon: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          IconButton(
            tooltip: s('report'),
            onPressed: () => unawaited(report()),
            icon: const Icon(Icons.ios_share),
          ),
          NexPopupMenuButton<String>(
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            enabled: !busy,
            icon: const Icon(Icons.more_vert),
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  unawaited(editFund());
                case 'unit':
                  paint(
                    () => unit = unit == IrrUnit.toman
                        ? IrrUnit.rial
                        : IrrUnit.toman,
                  );
              }
            },
            itemBuilder: (_) => [
              nexMenuItem(
                value: 'edit',
                icon: Icons.edit_outlined,
                label: s('editFund'),
              ),
              nexMenuItem(
                value: 'unit',
                icon: Icons.swap_horiz,
                label: s(unit == IrrUnit.toman ? 'rial' : 'toman'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(NexSpacing.sm),
              child: NexAdaptiveSegments<int>(
                segments: [
                  for (final (i, label) in [
                    'month',
                    'members',
                    'loans',
                  ].indexed)
                    ButtonSegment(value: i, label: Text(s(label))),
                ],
                selected: {tab},
                onSelectionChanged: busy
                    ? null
                    : (v) => paint(() {
                        tab = v.single;
                        if (scroll.hasClients) scroll.jumpTo(0);
                      }),
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            Expanded(
              child: AbsorbPointer(
                absorbing: busy,
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(NexSpacing.md),
                  children: [
                    NexSegmentSwap(
                      selection: tab,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: switch (tab) {
                          0 => monthView(),
                          1 => membersView(),
                          _ => loansView(),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
