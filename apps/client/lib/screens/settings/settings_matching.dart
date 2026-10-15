part of '../settings_sheet.dart';

/// What the search field at the top of Settings finds. Split out of
/// settings_sheet.dart (REL-10).
extension _SettingsMatching on SettingsSheet {
  /// Every row, from every section, that the query finds — each still the
  /// real row, so a switch found here is switched here (W6.6). A section
  /// whose own name matches brings all of its rows.
  List<Widget> _matching(
    BuildContext context,
    AppLocalizations l10n,
    String query,
  ) {
    final theme = Theme.of(context);
    final words = _fold(query).split(' ').where((w) => w.isNotEmpty);
    bool finds(String text) {
      final folded = _fold(text);
      return words.every(folded.contains);
    }

    final out = <Widget>[];
    // Modules are added and removed in Tools → Modules, not here; searching
    // for one still finds the way there.
    if (finds(
      '${l10n.modulesTitle} ${l10n.cycleTitle} Cycle period module چرخه پریود قاعدگی ماژول',
    )) {
      out.add(
        NexSurface(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: KeyedSubtree(
            key: const ValueKey('settings-search-cycle'),
            child: _Row(
              icon: Icons.water_drop_outlined,
              title: l10n.cycleTitle,
              value: l10n.cycleInModules,
              onTap: () => Navigator.push(
                context,
                NexPageRoute<void>(
                  builder: (_) => ModulesScreen(
                    services: services,
                    preferences: preferences,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    for (final group in _groups(context, l10n)) {
      if (group is! _Section) continue;
      final rows = finds(group.title)
          ? group.children
          : [
              for (final row in group.children)
                if (finds(_searchTextOf(row))) row,
            ];
      if (rows.isEmpty) continue;
      out.add(
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            NexSpacing.sm,
            NexSpacing.sm,
            NexSpacing.sm,
            NexSpacing.xs,
          ),
          child: Text(
            group.title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      out.add(
        NexSurface(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
      );
    }
    if (out.isEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.all(NexSpacing.xl),
          child: Text(
            nexLabel(
              context,
              'No setting matches that.',
              'تنظیمی با این عبارت پیدا نشد.',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return out;
  }
}
