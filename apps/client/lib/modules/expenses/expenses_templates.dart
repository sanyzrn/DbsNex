import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'expenses_fields.dart';
import 'expenses_undo.dart';
import 'models.dart';
import 'money.dart';
import 'strings.dart';
import 'editor_draft.dart';

part 'expenses_template_editor.dart';

/// Templates: a reusable entry the person confirms — a template fills
/// the transaction editor; nothing is ever charged in the background.
///
/// From the screen's Templates action: the list, a Use action per row
/// that opens the editor prefilled, deletion with Undo, and a New
/// template editor of its own.
Future<void> showExpensesTemplates(
  BuildContext context, {
  required ExpensesController controller,
  required void Function(ExpenseTemplate template) onUse,
}) => nexShowSheet(
  context: context,
  builder: (sheetContext) => ScaffoldMessenger(
    child: Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(sheetContext).colorScheme.surface,
      body: _TemplatesSheet(controller: controller, onUse: onUse),
    ),
  ),
);

class _TemplatesSheet extends StatefulWidget {
  const _TemplatesSheet({required this.controller, required this.onUse});

  final ExpensesController controller;
  final ValueChanged<ExpenseTemplate> onUse;

  @override
  State<_TemplatesSheet> createState() => _TemplatesSheetState();
}

class _TemplatesSheetState extends State<_TemplatesSheet> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  bool _busy = false;

  Future<void> _use(ExpenseTemplate template) async {
    Navigator.pop(context);
    widget.onUse(template);
  }

  Future<void> _delete(ExpenseTemplate template) async {
    if (_busy) return;
    // A template is the person's own setup; a stray tap on the row's
    // delete icon asks before anything goes, exactly like payments and
    // categories do.
    final answer = await nexShowDialog<String>(
      context: context,
      builder: (dialogContext) => NexAlertDialog(
        title: Text(expenseStrings(dialogContext, 'deleteTemplateTitle')),
        content: NexDialogBody(
          child: Text(expenseStrings(dialogContext, 'deleteTemplateBody')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(expenseStrings(dialogContext, 'cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, 'delete'),
            child: Text(expenseStrings(dialogContext, 'delete')),
          ),
        ],
      ),
    );
    if (answer != 'delete' || !mounted) return;
    setState(() => _busy = true);
    try {
      final messenger = ScaffoldMessenger.of(context);
      final message = expenseStrings(context, 'deletedTx'),
          undoLabel = expenseStrings(context, 'undo');
      final undoFailure = expenseStrings(context, 'undoFailed');
      await widget.controller.deleteTemplate(template.id);
      if (mounted) {
        ExpensesUndo.offer(
          messenger,
          message: message,
          undoLabel: undoLabel,
          failureMessage: undoFailure,
          restore: () => widget.controller.restoreTemplate(template.id),
        );
      }
    } catch (_) {
      if (mounted) expenseWriteFailure(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newTemplate() async {
    await showExpensesTemplateEditor(context, controller: widget.controller);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = expenseStrings;
    final templates = widget.controller.templates;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        0,
        NexSpacing.md,
        NexSpacing.md,
      ),
      children: [
        Text(s(context, 'templatesTitle'), style: theme.textTheme.titleLarge),
        const SizedBox(height: NexSpacing.xs),
        Text(
          s(context, 'templatesHint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        if (templates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NexSpacing.md),
            child: Text(s(context, 'noTemplates')),
          ),
        for (final template in templates)
          ListTile(
            title: Text(template.label),
            subtitle: Text(
              '${template.type == 'income' ? '+' : ''}'
              '${formatExpenseNumber(template.amount, expenseExponentOf(template.currency, null), persian: NexModuleStrings.persian(context))} ${template.currency}',
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: s(context, 'useTemplate'),
                  icon: const Icon(Icons.north_east),
                  onPressed: () => unawaited(_use(template)),
                ),
                IconButton(
                  tooltip: s(context, 'delete'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => unawaited(_delete(template)),
                ),
              ],
            ),
            onTap: () => unawaited(_use(template)),
          ),
        const Divider(),
        OutlinedButton.icon(
          key: const ValueKey('expenses-new-template'),
          onPressed: _busy ? null : () => unawaited(_newTemplate()),
          icon: const Icon(Icons.add),
          label: Text(s(context, 'newTemplate')),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }
}
