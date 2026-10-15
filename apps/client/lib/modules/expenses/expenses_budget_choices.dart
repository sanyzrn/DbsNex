part of 'expenses_budget.dart';

/// The overall limit / one category choice — custom rows, 48dp, with
/// the chosen one marked by a check (colour is never the only signal).
class _OverallOrCategory extends StatelessWidget {
  const _OverallOrCategory({
    required this.categoryId,
    required this.customCategories,
    required this.onChanged,
  });

  final String? categoryId;
  final List<ExpenseCategory> customCategories;
  final ValueChanged<String?> onChanged;

  String _nameOf(BuildContext context) {
    if (categoryId == null) return '';
    for (final custom in customCategories) {
      if (custom.id == categoryId) return custom.label;
    }
    return expenseStrings(context, categoryId!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overall = categoryId == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('expenses-budget-overall'),
          onTap: () => onChanged(null),
          borderRadius: BorderRadius.circular(NexRadius.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: NexSpacing.sm,
            ),
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              children: [
                Expanded(child: Text(expenseStrings(context, 'overallLimit'))),
                if (overall)
                  Icon(Icons.check, size: 20, color: scheme.primary)
                else
                  Icon(
                    Icons.circle_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
        InkWell(
          key: const ValueKey('expenses-budget-category'),
          onTap: () => unawaited(_pick(context)),
          borderRadius: BorderRadius.circular(NexRadius.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: NexSpacing.sm,
            ),
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(expenseStrings(context, 'budgetCategoryLabel')),
                      if (!overall)
                        Text(
                          _nameOf(context),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!overall)
                  Icon(Icons.check, size: 20, color: scheme.primary)
                else
                  Icon(
                    Icons.circle_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await nexShowSheet<String>(
      context: context,
      builder: (sheetContext) =>
          _BudgetCategoryList(customCategories: customCategories),
    );
    if (picked != null) onChanged(picked);
  }
}

class _BudgetCategoryList extends StatelessWidget {
  const _BudgetCategoryList({required this.customCategories});

  final List<ExpenseCategory> customCategories;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
      ),
      children: [
        Text(
          expenseStrings(context, 'chooseCategory'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: NexSpacing.sm),
        for (final id in defaultExpenseCategoryIds)
          ListTile(
            dense: true,
            title: Text(expenseStrings(context, id)),
            onTap: () => Navigator.pop(context, id),
          ),
        for (final custom in customCategories)
          ListTile(
            dense: true,
            title: Text(custom.label),
            onTap: () => Navigator.pop(context, custom.id),
          ),
      ],
    );
  }
}
