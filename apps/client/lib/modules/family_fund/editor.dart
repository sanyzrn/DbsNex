import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'amount_field.dart';
import 'draft_guard.dart';
import 'fund_text.dart';
import 'irr_unit.dart';
import 'model.dart';
import 'money_format.dart';
import 'strings.dart';

Future<void> openFundEditor(
  BuildContext context,
  NexModuleStore store, {
  required String keyName,
  required String title,
  required List<String> fields,
  required String? Function(Fields) validate,
  required Future<void> Function(Fields) save,
  NexModuleMonth? initial,
  String? description,
  IrrUnit unit = IrrUnit.toman,
  Map<String, String> initialValues = const {},
  String? monthLabel,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) => FundEditor(
    store: store,
    keyName: keyName,
    title: title,
    description: description,
    fields: fields,
    validate: validate,
    save: save,
    initial: initial,
    unit: unit,
    initialValues: initialValues,
    monthLabel: monthLabel,
  ),
);

class FundEditor extends StatefulWidget {
  const FundEditor({
    super.key,
    required this.store,
    required this.keyName,
    required this.title,
    required this.fields,
    required this.validate,
    required this.save,
    this.initial,
    this.description,
    required this.unit,
    this.initialValues = const {},
    this.monthLabel,
  });
  final NexModuleStore store;
  final String keyName, title;
  final String? description;
  final List<String> fields;
  final String? Function(Fields) validate;
  final Future<void> Function(Fields) save;
  final NexModuleMonth? initial;
  final IrrUnit unit;
  final Map<String, String> initialValues;
  final String? monthLabel;
  @override
  State<FundEditor> createState() => _FundEditorState();
}

class _FundEditorState extends State<FundEditor> {
  late final controllers = {
    for (final key in widget.fields)
      key: TextEditingController(
        text: switch (key) {
          'payDay' => '1',
          'drawDay' => '5',
          'shares' => '1',
          'count' => '6',
          _ => '',
        },
      ),
  };
  late var month = widget.initial;
  late var id = widget.store.newId();
  late final draft = NexModuleFormDraft(
    widget.store,
    widget.keyName,
    const {'v': 1},
    controllers,
    () => {
      'month': month == null ? null : dayKey(month!.first),
      'id': id,
      'amountUnit': widget.unit.key,
    },
  );
  bool loading = true, failed = false, busy = false, committed = false;
  String? error;

  String _monthLabel(BuildContext context) => fundStrings(
    context,
    widget.monthLabel ??
        (widget.fields.contains('shares')
            ? 'join'
            : widget.fields.contains('count')
            ? 'repayStart'
            : 'start'),
  );

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final data = await draft.load();
    if (!mounted) return;
    if (data != null) {
      draft.apply(data);
      if (data['id'] is String) id = data['id'] as String;
      final raw = DateTime.tryParse('${data['month']}');
      if (raw != null && widget.initial != null) month = fundMonth(raw);
      if (data['amountUnit'] != widget.unit.key) {
        final previous = IrrUnit.fromKey(data['amountUnit']);
        for (final field in ['shareAmount', 'principal']) {
          final c = controllers[field];
          if (c == null || c.text.isEmpty) continue;
          final amount = parseAmount(c.text, 'IRR', 0, previous);
          c.text = amount == null
              ? ''
              : amountInput(amount, 'IRR', 0, widget.unit);
        }
      }
    } else {
      // What the record already holds, so correcting it opens a filled form
      // rather than an empty one that would erase what is not retyped.
      for (final entry in widget.initialValues.entries) {
        final controller = controllers[entry.key];
        if (controller != null) controller.text = entry.value;
      }
    }
    setState(() {
      loading = false;
      failed = draft.loadFailed;
    });
    if (!failed) draft.start();
  }

  @override
  void dispose() {
    draft.close();
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!committed) {
        final data = <String, Object?>{
          'id': id,
          'month': month,
          for (final e in controllers.entries) e.key: e.value.text.trim(),
        };
        for (final key in ['shareAmount', 'principal']) {
          if (data[key] case final String raw) {
            data[key] = parseAmount(raw, 'IRR', 0, widget.unit);
          }
        }
        for (final key in ['shares', 'count', 'payDay', 'drawDay']) {
          if (data[key] case final String raw) data[key] = parseMoney(raw, 0);
        }
        final problem = widget.validate(data);
        if (problem != null) {
          if (mounted) setState(() => error = problem);
          return;
        }
        await widget.save(data);
        committed = true;
      }
      if (await draft.clear()) {
        if (mounted) Navigator.pop(context);
      } else if (mounted) {
        setState(() => error = 'saveError');
      }
    } on Object {
      if (mounted) setState(() => error = 'saveError');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = fundStrings;
    return NexModuleCalendar(
      solar: true,
      child: DraftGuard(
        draft: draft,
        busy: () => loading || busy,
        child: Builder(
          builder: (context) => SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(NexSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (loading)
                    const LinearProgressIndicator()
                  else if (failed) ...[
                    Text(s(context, 'loadError')),
                    TextButton(
                      onPressed: () {
                        setState(() => loading = true);
                        load();
                      },
                      child: Text(s(context, 'retry')),
                    ),
                  ] else ...[
                    Flexible(
                      child: SingleChildScrollView(
                        child: AbsorbPointer(
                          absorbing: busy || committed,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.description case final description?)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    bottom: NexSpacing.sm,
                                  ),
                                  child: Text(
                                    description,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              for (final e in controllers.entries)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: NexSpacing.md,
                                  ),
                                  child:
                                      [
                                        'shareAmount',
                                        'principal',
                                      ].contains(e.key)
                                      ? AmountField(
                                          controller: e.value,
                                          currency: 'IRR',
                                          digits: 0,
                                          unit: widget.unit,
                                          label: s(context, e.key),
                                        )
                                      : NexTextField(
                                          controller: e.value,
                                          minLines: 1,
                                          maxLines:
                                              [
                                                'rules',
                                                'reason',
                                              ].contains(e.key)
                                              ? 3
                                              : 1,
                                          maxLength: e.key == 'rules'
                                              ? 3000
                                              : 120,
                                          keyboardType:
                                              [
                                                'shares',
                                                'count',
                                                'payDay',
                                                'drawDay',
                                              ].contains(e.key)
                                              ? TextInputType.number
                                              : TextInputType.text,
                                          decoration: InputDecoration(
                                            labelText: s(context, e.key),
                                          ),
                                        ),
                                ),
                              if (month != null)
                                TextButton.icon(
                                  icon: const Icon(
                                    Icons.calendar_month_outlined,
                                  ),
                                  label: Text(
                                    '${_monthLabel(context)}${fundSep(context)}${month!.title(context)}',
                                  ),
                                  onPressed: () async {
                                    final picked = await nexPickModuleDate(
                                      context,
                                      initial: month!.first,
                                      first: DateTime(1922, 3, 22),
                                      last: DateTime(2099, 12, 31),
                                    );
                                    if (picked != null && mounted) {
                                      setState(() => month = fundMonth(picked));
                                      draft.changed();
                                    }
                                  },
                                ),
                              if (widget.fields.contains('count'))
                                Text(s(context, 'repayHint')),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (error != null)
                      Text(
                        s(context, error!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: Text(s(context, committed ? 'retry' : 'save')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
