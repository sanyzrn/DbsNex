import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'expenses_fields.dart' show expenseCategoryIcon;
import 'expenses_undo.dart';
import 'models.dart';
import 'strings.dart';
import 'editor_draft.dart';

/// The categories management sheet. A small, focused `nexShowSheet` —
/// never a page, never a dialog — and its deletion offers Undo in the
/// screen's own messenger.

/// Categories: the built-in eleven (read-only, from the strings) and
/// the person's own, which can be added and deleted. Deleting a custom
/// category leaves records untouched; they read as "Other".
Future<void> showExpensesCategories(
  BuildContext context, {
  required ExpensesController controller,
}) => nexShowSheet(
  context: context,
  builder: (sheetContext) => ScaffoldMessenger(
    child: Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(sheetContext).colorScheme.surface,
      body: _CategoriesSheet(controller: controller),
    ),
  ),
);

class _CategoriesSheet extends StatefulWidget {
  const _CategoriesSheet({required this.controller});

  final ExpensesController controller;

  @override
  State<_CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends State<_CategoriesSheet> {
  final _name = TextEditingController();
  bool _busy = false;
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
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final label = _name.text.trim();
    if (label.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.controller.addCategory(label);
      _name.clear();
    } catch (_) {
      if (mounted) expenseWriteFailure(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = expenseStrings;
    final custom = widget.controller.customCategories;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        0,
        NexSpacing.md,
        NexSpacing.md,
      ),
      children: [
        Text(s(context, 'categoriesTitle'), style: theme.textTheme.titleLarge),
        const SizedBox(height: NexSpacing.sm),
        for (final id in defaultExpenseCategoryIds)
          ListTile(
            dense: true,
            leading: Icon(
              expenseCategoryIcon(id),
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(s(context, id)),
            trailing: Icon(
              Icons.lock_outline,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (custom.isNotEmpty) ...[
          const Divider(),
          for (final category in custom)
            ListTile(
              dense: true,
              leading: Icon(
                expenseCategoryIcon(category.id),
                color: theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(category.label),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A name typed once should be correctable: renaming keeps
                  // the id, so every record written with it follows.
                  IconButton(
                    key: ValueKey('expenses-rename-${category.id}'),
                    tooltip: s(context, 'rename'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => unawaited(_renameCategory(category)),
                  ),
                  IconButton(
                    tooltip: s(context, 'delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => unawaited(_deleteCategory(category)),
                  ),
                ],
              ),
            ),
        ],
        const Divider(),
        Text(
          s(context, 'defaultCategoryNote'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        Row(
          children: [
            Expanded(
              child: NexAutoDirection(
                controller: _name,
                builder: (context, direction) => TextField(
                  key: const ValueKey('expenses-new-category'),
                  controller: _name,
                  textDirection: direction,
                  decoration: InputDecoration(
                    labelText: s(context, 'newCategory'),
                    hintText: s(context, 'categoryNameHint'),
                    errorText:
                        _name.text.trim().isEmpty && _name.text.isNotEmpty
                        ? s(context, 'categoryNameEmpty')
                        : null,
                  ),
                  onSubmitted: (_) => unawaited(_add()),
                ),
              ),
            ),
            const SizedBox(width: NexSpacing.sm),
            IconButton(
              key: const ValueKey('expenses-add-category'),
              tooltip: s(context, 'add'),
              onPressed: _busy ? null : () => unawaited(_add()),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _renameCategory(ExpenseCategory category) async {
    final name = await nexShowDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _RenameCategoryDialog(initial: category.label),
    );
    if (name == null || !mounted) return;
    final label = name.trim();
    if (label.isEmpty || label == category.label) return;
    try {
      await widget.controller.renameCategory(category, label);
      if (mounted) {
        NexBannerHost.of(context)
            ?.show(message: expenseStrings(context, 'categoryRenamed'));
      }
    } catch (_) {
      if (mounted) expenseWriteFailure(context);
    }
  }

  Future<void> _deleteCategory(ExpenseCategory category) async {
    final answer = await nexShowDialog<String>(
      context: context,
      builder: (dialogContext) => NexAlertDialog(
        title: Text(expenseStrings(dialogContext, 'deleteCategoryTitle')),
        content: NexDialogBody(
          child: Text(expenseStrings(dialogContext, 'deleteCategoryBody')),
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
    final messenger = NexBannerHost.of(context);
    final message = expenseStrings(context, 'deletedTx');
    final undoLabel = expenseStrings(context, 'undo');
    final undoFailure = expenseStrings(context, 'undoFailed');
    try {
      await widget.controller.deleteCategory(category);
      if (mounted) {
        ExpensesUndo.offer(
          messenger,
          message: message,
          undoLabel: undoLabel,
          failureMessage: undoFailure,
          restore: () => widget.controller.restoreCategory(category),
        );
      }
    } catch (_) {
      if (mounted) expenseWriteFailure(context);
    }
  }
}

/// Renames one of the person's own categories. The id — and so every record
/// written with it — stays; only the word changes.
class _RenameCategoryDialog extends StatefulWidget {
  const _RenameCategoryDialog({required this.initial});

  final String initial;

  @override
  State<_RenameCategoryDialog> createState() => _RenameCategoryDialogState();
}

class _RenameCategoryDialogState extends State<_RenameCategoryDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _name.text.trim();
    if (label.isEmpty) return;
    Navigator.pop(context, label);
  }

  @override
  Widget build(BuildContext context) {
    final s = expenseStrings;
    final theme = Theme.of(context);
    return NexAlertDialog(
      title: Text(s(context, 'renameCategoryTitle')),
      content: NexDialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s(context, 'renameCategoryHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            NexAutoDirection(
              controller: _name,
              builder: (context, direction) => TextField(
                key: const ValueKey('expenses-rename-category'),
                controller: _name,
                autofocus: true,
                textDirection: direction,
                decoration: InputDecoration(
                  labelText: s(context, 'newCategory'),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s(context, 'cancel')),
        ),
        TextButton(onPressed: _submit, child: Text(s(context, 'save'))),
      ],
    );
  }
}
