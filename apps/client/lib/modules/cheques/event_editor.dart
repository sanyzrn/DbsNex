import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'reminders.dart';
import 'repository.dart';
import 'strings.dart';
import 'privacy.dart';
import 'values.dart';
import 'widgets.dart';
import 'draft_guard.dart';
import 'amount_field.dart';
import 'irr_unit.dart';

class ChequeEventEditor extends StatefulWidget {
  const ChequeEventEditor({
    super.key,
    required this.repo,
    required this.cheque,
    required this.payment,
  });
  final ChequeRepository repo;
  final Cheque cheque;
  final bool payment;
  @override
  State<ChequeEventEditor> createState() => _ChequeEventEditorState();
}

class _ChequeEventEditorState extends State<ChequeEventEditor> {
  final _fields = <String, TextEditingController>{
    for (final k in ['amount', 'target', 'note']) k: TextEditingController(),
  };
  late String _id = widget.repo.store.newId();
  late String _unit = widget.cheque.unit;
  late DateTime _day = DateTime.now();
  late String _next = allowed.first;
  List<String> get allowed => [
    for (final s in [
      'active',
      'registered',
      'handed',
      'deposited',
      'bounced',
      'transferred',
      'returned',
      'cancelled',
    ])
      if (s != widget.cheque.status &&
          !(widget.cheque.direction == 'outgoing' &&
              ['deposited', 'transferred'].contains(s)) &&
          !(widget.cheque.purpose == 'guarantee' &&
              ['deposited', 'transferred'].contains(s)))
        s,
  ];
  late final _draft = NexModuleFormDraft(
    widget.repo.store,
    'action:${widget.cheque.id}',
    {...widget.cheque.raw, 'actionType': widget.payment ? 'payment' : 'status'},
    _fields,
    () => {
      'recordId': _id,
      'unit': _unit,
      'day': chequeDayKey(_day),
      'next': _next,
    },
  );
  bool _loading = true, _failed = false, _saving = false;
  bool _reading = false;
  String? _error;
  Cheque? _committed;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_reading) return;
    _reading = true;
    final data = await _draft.load();
    _reading = false;
    if (!mounted) return;
    if (_draft.loadFailed) {
      setState(() {
        _failed = true;
        _loading = false;
      });
      return;
    }
    if (data != null) {
      _draft.apply(data);
      if (data['recordId'] is String &&
          RegExp(r'^[0-9a-f-]{36}$').hasMatch(data['recordId'] as String)) {
        _id = data['recordId'] as String;
      }
      if (['rial', 'toman'].contains(data['unit'])) {
        _unit = data['unit'] as String;
      }
      _day = chequeDay(data['day']) ?? _day;
      if (allowed.contains(data['next'])) _next = data['next'] as String;
    }
    _draft.start();
    setState(() {
      _failed = false;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _draft.close();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_loading || _saving || _failed) return;
    final s = chequeStrings;
    final amount = editableAmount(
      _fields['amount']!.text,
      _unit,
      original: widget.cheque.remaining,
    );
    if (_committed == null &&
        widget.payment &&
        (amount == null || amount > widget.cheque.remaining)) {
      setState(() => _error = s(context, 'paymentError'));
      return;
    }
    if (_committed == null) {
      final yes = await nexShowDialog<bool>(
        context: context,
        builder: (c) => NexAlertDialog(
          title: Text(s(c, 'confirmAction')),
          content: NexDialogBody(
            child: Text(
              [
                widget.cheque.party,
                widget.payment
                    ? '${chequeMoney(c, amount!, unit: _unit)} ${s(c, _unit)}'
                    : s(c, 'status_$_next'),
                nexModuleDateLabel(c, _day),
                _fields['target']!.text,
              ].where((v) => v.isNotEmpty).join('\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(AppLocalizations.of(c).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(s(c, 'eventSave')),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      _committed ??= await widget.repo.addEvent(
        widget.cheque,
        id: _id,
        kind: widget.payment ? 'payment' : 'status',
        day: _day,
        amount: amount?.toString() ?? '',
        next: _next,
        note: _fields['note']!.text,
        target: _fields['target']!.text,
      );
      if (!await _draft.clear()) {
        if (mounted) {
          setState(() {
            _saving = false;
            _error = s(context, 'cleanup');
          });
        }
        return;
      }
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      var ok = true;
      try {
        ok = await armCheque(widget.repo.store, _committed!, l10n);
      } catch (_) {
        ok = false;
      }
      if (!mounted) return;
      if (!ok) {
        nexShowBanner(
          context,
          message: s(context, 'remindError'),
          kind: NexBannerKind.failed,
        );
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = s(context, e is ChequeFailure ? e.code : 'saveError');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = chequeStrings;
    return DraftGuard(
      draft: _draft,
      busy: () => _loading || _saving,
      child: Scaffold(
        appBar: NexAppBar(
          title: Text(s(context, widget.payment ? 'settle' : 'statusChange')),
          actions: const [ChequePrivacyButton()],
        ),
        body: _failed
            ? NexEmptyState(
                icon: Icons.refresh,
                message: s(context, 'readError'),
                action: TextButton(
                  onPressed: _load,
                  child: Text(s(context, 'retry')),
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  NexSpacing.md,
                  NexSpacing.md,
                  NexSpacing.md,
                  NexSpacing.xl + nexBottomInset(context),
                ),
                children: [
                  Text(
                    widget.cheque.party,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${s(context, 'remaining')}: ${chequeMoney(context, widget.cheque.remaining, unit: widget.cheque.unit)} ${s(context, widget.cheque.unit)}',
                  ),
                  const SizedBox(height: NexSpacing.md),
                  AbsorbPointer(
                    absorbing: _loading || _saving || _committed != null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.payment) ...[
                          ChequeChoices(
                            values: const ['toman', 'rial'],
                            value: _unit,
                            onChanged: (v) {
                              final n = enteredAmount(
                                _fields['amount']!.text,
                                _unit,
                              );
                              if (n != null &&
                                  v == 'toman' &&
                                  n % BigInt.from(10) != BigInt.zero) {
                                setState(
                                  () => _error = s(context, 'unitError'),
                                );
                                return;
                              }
                              setState(() {
                                if (n != null) {
                                  _fields['amount']!.text = amountForEdit(n, v);
                                }
                                _unit = v;
                              });
                              _draft.changed();
                            },
                          ),
                          const SizedBox(height: NexSpacing.sm),
                          ChequePrivateInput(
                            hidden: chequeHidden(context),
                            child: AmountField(
                              fieldKey: const ValueKey('cheque-event-amount'),
                              controller: _fields['amount']!,
                              currency: 'IRR',
                              digits: 0,
                              unit: IrrUnit.fromKey(_unit),
                              label: s(context, 'amount'),
                            ),
                          ),
                        ] else ...[
                          ChequeChoices(
                            values: allowed,
                            value: _next,
                            prefix: 'status_',
                            onChanged: (v) {
                              setState(() => _next = v);
                              _draft.changed();
                            },
                          ),
                          const SizedBox(height: NexSpacing.md),
                          NexTextField(
                            key: const ValueKey('cheque-target'),
                            controller: _fields['target']!,
                            minLines: 1,
                            maxLines: 2,
                            maxLength: 100,
                            decoration: InputDecoration(
                              labelText: s(context, 'target'),
                              counterText: '',
                            ),
                          ),
                        ],
                        const SizedBox(height: NexSpacing.md),
                        TextButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await nexPickModuleDate(
                              context,
                              initial: _day.isAfter(now) ? now : _day,
                              first: DateTime(1900),
                              last: now,
                            );
                            if (picked != null && mounted) {
                              setState(() => _day = picked);
                              _draft.changed();
                            }
                          },
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            '${s(context, 'eventDay')}: ${nexModuleDateLabel(context, _day)}',
                          ),
                        ),
                        const SizedBox(height: NexSpacing.md),
                        NexTextField(
                          key: const ValueKey('cheque-event-note'),
                          controller: _fields['note']!,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 500,
                          decoration: InputDecoration(
                            labelText: s(context, 'eventNote'),
                            counterText: '',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  Text(
                    s(context, 'personalOnly'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: NexSpacing.md),
                  FilledButton.icon(
                    key: const ValueKey('cheque-event-save'),
                    onPressed: _loading || _saving ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(
                      s(context, _committed == null ? 'eventSave' : 'retry'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
