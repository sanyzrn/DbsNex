import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../modules/module_hero.dart';
import '../modules/module_shared.dart';
import '../modules/nex_module_store.dart';
import '../modules/nex_stored_module.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import 'nex_dialog.dart';
import 'tool_dates.dart';

/// A module's quick view (2.8.5): what a tap on its pinned tile opens first,
/// the way a tap on a note opens its details — the module's facts at a
/// glance and what it has coming up, with the module itself one button away
/// for anything more.
Future<void> nexShowModulePeek(
  BuildContext context, {
  required NexStoredModule module,
  required NexServices services,
  required NexPreferences preferences,
}) async {
  final open = await nexShowSheet<bool>(
    context: context,
    builder: (_) => ModulePeek(
      module: module,
      services: services,
      preferences: preferences,
    ),
  );
  if (open != true || !context.mounted) return;
  await Navigator.of(context).push(
    NexPageRoute<void>(
      builder: (_) => module.open(services: services, preferences: preferences),
    ),
  );
}

class ModulePeek extends StatefulWidget {
  const ModulePeek({
    super.key,
    required this.module,
    required this.services,
    required this.preferences,
    this.clock,
  });

  final NexStoredModule module;
  final NexServices services;
  final NexPreferences preferences;
  final DateTime Function()? clock;

  /// How far ahead the quick view looks for dates.
  static const ahead = Duration(days: 31);

  @override
  State<ModulePeek> createState() => _ModulePeekState();
}

class _ModulePeekState extends State<ModulePeek> {
  Future<(ModuleGlance?, List<ModuleDue>)>? _data;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once, in the language the sheet is shown in.
    _data ??= _load(AppLocalizations.of(context));
  }

  Future<(ModuleGlance?, List<ModuleDue>)> _load(AppLocalizations l10n) async {
    final store = NexModuleStore(widget.services, widget.module.id);
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    ModuleGlance? glance;
    var dues = const <ModuleDue>[];
    try {
      glance = await widget.module.glance(store, l10n, now);
    } catch (_) {
      // The module itself still opens; the quick view says less.
    }
    try {
      dues = [
        for (final due in await widget.module.dues(
          store,
          today.subtract(const Duration(days: 60)),
          today.add(ModulePeek.ahead),
        ))
          if (!due.done) due,
      ]..sort((a, b) => a.at.compareTo(b.at));
    } catch (_) {}
    return (glance, dues);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = nexModuleAccent(context, widget.module.id);
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.lg,
        NexSpacing.sm,
        NexSpacing.lg,
        NexSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(NexRadius.md),
                ),
                child: Icon(widget.module.icon, color: accent),
              ),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.module.title(l10n),
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      widget.module.tagline(l10n),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          Flexible(
            child: FutureBuilder<(ModuleGlance?, List<ModuleDue>)>(
              future: _data,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(NexSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final (glance, dues) = snapshot.data!;
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (glance == null && dues.isEmpty)
                        Text(
                          l10n.peekNothing,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (glance != null) ...[
                        Text(
                          glance.headline,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (glance.detail case final detail?)
                          Text(
                            detail,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        if (glance.progress case final progress?) ...[
                          const SizedBox(height: NexSpacing.sm),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(NexRadius.pill),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              color: accent,
                              backgroundColor: accent.withValues(alpha: 0.15),
                            ),
                          ),
                        ],
                        if (glance.facts.isNotEmpty) ...[
                          const SizedBox(height: NexSpacing.md),
                          for (final fact in glance.facts) _FactRow(fact: fact),
                        ],
                      ],
                      if (dues.isNotEmpty) ...[
                        const SizedBox(height: NexSpacing.md),
                        Text(
                          l10n.peekComing,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: NexSpacing.xs),
                        for (final due in dues.take(6))
                          _DueRow(
                            title: switch (widget.module.dueLabel(
                              l10n,
                              due.kind,
                            )) {
                              null => due.title,
                              final what when due.title.isEmpty => what,
                              final what => l10n.toolDatesWhat(due.title, what),
                            },
                            when: nexToolDateWhen(l10n, due.at, today),
                            late: due.at.isBefore(today),
                          ),
                        if (dues.length > 6)
                          Text(
                            l10n.toolDatesMore(dues.length - 6),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          FilledButton.icon(
            key: const ValueKey('peek-open'),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(l10n.peekOpen(widget.module.title(l10n))),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});
  final ModuleGlanceFact fact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              fact.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: NexSpacing.sm),
          Flexible(
            child: Text(
              fact.value,
              textAlign: TextAlign.end,
              style:
                  (fact.strong
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(
                        fontWeight: fact.strong ? FontWeight.w700 : null,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.title, required this.when, required this.late});
  final String title;
  final String when;
  final bool late;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
      child: Row(
        children: [
          Icon(
            Icons.event_outlined,
            size: 16,
            color: late ? scheme.error : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            when,
            style: theme.textTheme.labelMedium?.copyWith(
              color: late ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
