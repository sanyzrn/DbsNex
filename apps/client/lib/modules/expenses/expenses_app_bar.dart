import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'strings.dart';

/// The home's bar: the module's name, the eye that hides the amounts, the
/// search, and the menu of everything else (budgets, categories, templates,
/// sharing the month).
class ExpensesAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ExpensesAppBar({
    super.key,
    required this.title,
    required this.hiddenAmounts,
    required this.searching,
    required this.showShare,
    required this.onToggleAmounts,
    required this.onSearch,
    required this.onMenu,
  });

  final String title;
  final bool hiddenAmounts;
  final bool searching;
  final bool showShare;
  final VoidCallback onToggleAmounts;
  final VoidCallback onSearch;
  final ValueChanged<String> onMenu;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final s = expenseStrings;
    return NexAppBar(
      title: Text(title),
      actions: [
        IconButton(
          tooltip: s(context, hiddenAmounts ? 'showAmounts' : 'hideAmounts'),
          onPressed: onToggleAmounts,
          icon: Icon(
            hiddenAmounts
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
        IconButton(
          tooltip: s(context, 'searchLabel'),
          onPressed: onSearch,
          icon: Icon(searching ? Icons.search_off : Icons.search),
        ),
        NexPopupMenuButton<String>(
          tooltip: s(context, 'menuLabel'),
          onSelected: onMenu,
          itemBuilder: (menuContext) => [
            nexMenuItem(
              value: 'budgets',
              icon: Icons.savings_outlined,
              label: s(menuContext, 'budgetsTitle'),
            ),
            nexMenuItem(
              value: 'categories',
              icon: Icons.category_outlined,
              label: s(menuContext, 'categoriesTitle'),
            ),
            nexMenuItem(
              value: 'templates',
              icon: Icons.bookmarks_outlined,
              label: s(menuContext, 'templatesTitle'),
            ),
            if (showShare)
              nexMenuItem(
                value: 'share',
                icon: Icons.ios_share_outlined,
                label: s(menuContext, 'shareMonth'),
              ),
          ],
        ),
      ],
    );
  }
}
