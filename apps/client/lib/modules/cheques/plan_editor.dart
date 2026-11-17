import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'plan_model.dart';
import 'plan_repository.dart';
import 'repository.dart';
import 'privacy.dart';
import 'reminders.dart';
import 'strings.dart';
import 'values.dart';
import 'widgets.dart';

class PlanEditor extends StatefulWidget {
  const PlanEditor({super.key, required this.repo, this.plan});
  final PlanRepository repo;
  final InstalmentPlan? plan;
  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  late final fields = {
    'title': TextEditingController(text: widget.plan?.title ?? ''),
    'total': TextEditingController(text: widget.plan?.total?.toString() ?? ''),
    'count': TextEditingController(text: '${widget.plan?.count ?? 4}'),
    'before': TextEditingController(
      text: '${widget.plan?.raw['beforeDays'] ?? 3}',
    ),
    'months': TextEditingController(text: '${widget.plan?.months ?? 1}'),
  };
  late DateTime day = widget.plan?.first ?? DateTime.now();
  late String calendar = widget.plan?.raw['calendar'] as String? ?? 'jalali',
      id = widget.plan?.id ?? widget.repo.store.newId();
  late bool remind = widget.plan?.raw['remind'] == true;
  late final draft = NexModuleFormDraft(
    widget.repo.store,
    'plan:${widget.plan?.id ?? 'new'}',
    widget.plan?.raw ?? const {},
    fields,
    () => {
      'recordId': id,
      'day': chequeDayKey(day),
      'calendar': calendar,
      'remind': remind,
    },
  );
  bool loading = true, failed = false, busy = false;
  String? error;
  InstalmentPlan? committed;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final data = await draft.load();
    if (!mounted) return;
    if (draft.loadFailed) {
      setState(() {
        loading = false;
        failed = true;
      });
      return;
    }
    if (data != null) {
      draft.apply(data);
      day = chequeDay(data['day']) ?? day;
      if (['jalali', 'gregorian'].contains(data['calendar'])) {
        calendar = data['calendar'] as String;
      }
      if (widget.plan == null && data['recordId'] is String) {
        id = data['recordId'] as String;
      }
      remind = data['remind'] == true;
    }
    draft.start();
    setState(() {
      loading = false;
      failed = false;
    });
  }

  @override
  void dispose() {
    draft.close();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || loading || failed) return;
    setState(() => busy = true);
    try {
      committed ??= await widget.repo.save(id, widget.plan?.raw, {
        'title': fields['title']!.text.trim(),
        'totalRial':
            enteredAmount(fields['total']!.text, 'rial')?.toString() ?? '',
        'count': int.tryParse(chequeDigits(fields['count']!.text)) ?? 0,
        'months': int.tryParse(chequeDigits(fields['months']!.text)) ?? 0,
        'first': chequeDayKey(day),
        'calendar': calendar,
        'remind': remind,
        'beforeDays': int.tryParse(chequeDigits(fields['before']!.text)) ?? -1,
        'minutes': 540,
      });
      if (!await draft.clear()) {
        if (mounted) {
          setState(() {
            busy = false;
            error = chequeStrings(context, 'cleanup');
          });
        }
        return;
      }
      if (mounted) {
        var ok = false;
        try {
          ok = await renewPlans(
            widget.repo.store,
            AppLocalizations.of(context),
          );
        } catch (_) {
          ok = false;
        }
        if (mounted) {
          if (!ok) {
            nexShowBanner(
              context,
              message: chequeStrings(context, 'remindError'),
              kind: NexBannerKind.failed,
            );
          }
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = chequeStrings(
            context,
            e is ChequeFailure ? e.code : 'saveError',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = chequeStrings;
    return ChequeDraftGuard(
      draft: draft,
      busy: () => busy || loading,
      child: Scaffold(
        appBar: NexAppBar(
          title: Text(s(context, 'addPlan')),
          actions: const [ChequePrivacyButton()],
        ),
        body: failed
            ? NexEmptyState(
                icon: Icons.refresh,
                message: s(context, 'readError'),
                action: TextButton(
                  onPressed: load,
                  child: Text(s(context, 'retry')),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(NexSpacing.md),
                children: [
                  AbsorbPointer(
                    absorbing: loading || busy || committed != null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              fields['count']!.text = '4';
                              fields['months']!.text = '1';
                            });
                            draft.changed();
                          },
                          child: Text(s(context, 'bnpl')),
                        ),
                        for (final k in fields.keys)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: NexSpacing.md,
                            ),
                            child: ChequePrivateInput(
                              hidden: k == 'total' && chequeHidden(context),
                              child: NexTextField(
                                key: ValueKey('plan-$k'),
                                controller: fields[k]!,
                                minLines: 1,
                                maxLines: 1,
                                maxLength: k == 'title' ? 100 : 32,
                                keyboardType: k == 'title'
                                    ? TextInputType.text
                                    : TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: s(context, 'plan_$k'),
                                  counterText: '',
                                ),
                              ),
                            ),
                          ),
                        Text(s(context, 'planHint')),
                        ChequeChoices(
                          values: const ['jalali', 'gregorian'],
                          value: calendar,
                          onChanged: (v) {
                            setState(() => calendar = v);
                            draft.changed();
                          },
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final d = await nexPickModuleDate(
                              context,
                              initial: day,
                              first: DateTime(1900),
                              last: DateTime(2090),
                            );
                            if (d != null && mounted) {
                              setState(() => day = d);
                              draft.changed();
                            }
                          },
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(nexModuleDateLabel(context, day)),
                        ),
                        SwitchListTile.adaptive(
                          value: remind,
                          onChanged: (v) {
                            setState(() => remind = v);
                            draft.changed();
                          },
                          title: Text(s(context, 'remind')),
                        ),
                      ],
                    ),
                  ),
                  if (error != null) Text(error!),
                  FilledButton(
                    onPressed: loading || busy ? null : save,
                    child: Text(s(context, 'savePlan')),
                  ),
                ],
              ),
      ),
    );
  }
}
