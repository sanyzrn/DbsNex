import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../modules/module_plans.dart';
import '../modules/module_registry.dart';
import '../platform/nex_preferences.dart';
import '../platform/feedback_service.dart';
import '../platform/nex_services.dart';
import '../widgets/feedback_sheet.dart';
import '../widgets/nex_shelf.dart';

/// Tools → Modules: every optional feature Nex ships, and the one place to
/// add or remove each — see `docs/17-modules.md`.
///
/// A card per module, in the module's own colour: what it is, what it does
/// as a few chips, and one action — Add, or Open and Remove. Added modules
/// come first, so the page answers "what have I got" before "what else is
/// there".
class ModulesScreen extends StatefulWidget {
  const ModulesScreen({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  /// The module whose add or remove is under way, so its buttons do not
  /// take a second tap while the first is still asking its question.
  String? _busy;

  Future<void> _toggle(NexModule module, bool on) async {
    if (_busy != null) return;
    setState(() => _busy = module.id);
    try {
      if (on) {
        await module.turnOn(
          context,
          services: widget.services,
          preferences: widget.preferences,
        );
      } else {
        await module.turnOff(
          context,
          services: widget.services,
          preferences: widget.preferences,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _open(NexModule module) => unawaited(
    Navigator.push(
      context,
      NexPageRoute<void>(
        builder: (_) => module.open(
          services: widget.services,
          preferences: widget.preferences,
        ),
      ),
    ),
  );

  /// An idea for a module goes the way any other word to the developer
  /// does: the feedback sheet.
  Future<void> _suggest() async {
    final service = FeedbackService(preferences: widget.preferences);
    await FeedbackSheet.show(context, service: service);
    service.close();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.modulesTitle)),
      body: ListenableBuilder(
        listenable: widget.preferences,
        builder: (context, _) {
          final added = [
            for (final m in nexModules)
              if (m.isOn(widget.preferences)) m,
          ];
          final available = [
            for (final m in nexModules)
              if (!m.isOn(widget.preferences)) m,
          ];
          Widget card(NexModule module) => Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.md),
            child: _ModuleCard(
              module: module,
              on: module.isOn(widget.preferences),
              busy: _busy == module.id,
              onAdd: () => unawaited(_toggle(module, true)),
              onRemove: () => unawaited(_toggle(module, false)),
              onOpen: () => _open(module),
            ),
          );
          return ListView(
            padding: EdgeInsets.fromLTRB(
              NexSpacing.md,
              NexSpacing.sm,
              NexSpacing.md,
              NexSpacing.lg + nexBottomInset(context),
            ),
            children: [
              _Intro(text: l10n.modulesIntro),
              const SizedBox(height: NexSpacing.lg),
              NexShelfHeading(
                icon: Icons.check_circle_outline,
                title: l10n.modulesAdded,
              ),
              const SizedBox(height: NexSpacing.sm),
              if (added.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: NexSpacing.md),
                  child: Text(
                    l10n.modulesEmpty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ...added.map(card),
              if (available.isNotEmpty) ...[
                const SizedBox(height: NexSpacing.sm),
                NexShelfHeading(
                  icon: Icons.add_circle_outline,
                  title: l10n.modulesAvailable,
                ),
                const SizedBox(height: NexSpacing.sm),
                ...available.map(card),
              ],
              const SizedBox(height: NexSpacing.sm),
              NexShelfHeading(
                icon: Icons.schedule_outlined,
                title: l10n.modulesComing,
              ),
              const SizedBox(height: NexSpacing.sm),
              for (final plan in nexModulePlans)
                Padding(
                  padding: const EdgeInsets.only(bottom: NexSpacing.sm),
                  child: _PlanCard(plan: plan),
                ),
              const SizedBox(height: NexSpacing.sm),
              _SuggestRow(onTap: _suggest),
              const SizedBox(height: NexSpacing.md),
              Text(
                l10n.modulesMore,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The page's opening lines, on a soft panel with a puzzle-piece glyph.
class _Intro extends StatelessWidget {
  const _Intro({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(NexSpacing.md),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(NexRadius.xl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(NexRadius.md + 2),
            ),
            child: Icon(Icons.extension_outlined, color: scheme.onPrimary),
          ),
          const SizedBox(width: NexSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.on,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
    required this.onOpen,
  });

  final NexModule module;
  final bool on;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = module.hue.of(theme.brightness);
    return Container(
      key: ValueKey('module-${module.id}'),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: on ? 0.1 : 0.05),
          scheme.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(NexRadius.xl),
        border: Border.all(color: color.withValues(alpha: on ? 0.45 : 0.25)),
      ),
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(NexRadius.md + 2),
                ),
                child: Icon(module.icon, color: color, size: 26),
              ),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title(l10n),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      module.tagline(l10n),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (on) Icon(Icons.check_circle, color: color),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          Text(
            module.about(l10n),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              for (final point in module.points(l10n))
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(NexRadius.pill),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NexSpacing.md - 4,
                      vertical: 5,
                    ),
                    child: Text(
                      point,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          if (on)
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: ValueKey('module-${module.id}-open'),
                    onPressed: busy ? null : onOpen,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(l10n.moduleOpen),
                  ),
                ),
                const SizedBox(width: NexSpacing.sm),
                TextButton(
                  key: ValueKey('module-${module.id}-remove'),
                  onPressed: busy ? null : onRemove,
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  child: Text(l10n.moduleRemove),
                ),
              ],
            )
          else
            FilledButton.icon(
              key: ValueKey('module-${module.id}-add'),
              onPressed: busy ? null : onAdd,
              icon: const Icon(Icons.add),
              label: Text(l10n.moduleAdd),
            ),
        ],
      ),
    );
  }
}

/// A module still to come: its glyph, its name with a badge for how near it
/// is, and a line on what it will do. Quieter than an available module's
/// card — no wash of colour, no button — since there is nothing to do with
/// it yet but know it is coming.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final NexModulePlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = plan.hue.of(theme.brightness);
    final soon = plan.stage == NexModuleStage.soon;
    return Container(
      key: ValueKey('plan-${plan.id}'),
      padding: const EdgeInsets.all(NexSpacing.md - 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(NexRadius.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(NexRadius.md),
            ),
            child: Icon(plan.icon, color: color, size: 22),
          ),
          const SizedBox(width: NexSpacing.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      plan.title(l10n),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: soon
                            ? color.withValues(alpha: 0.16)
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(NexRadius.pill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexSpacing.sm,
                          vertical: 2,
                        ),
                        child: Text(
                          soon ? l10n.moduleStageSoon : l10n.moduleStagePlanned,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: soon
                                ? nexReadableOn(
                                    color,
                                    scheme.surfaceContainerLow,
                                  )
                                : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NexSpacing.xs),
                Text(
                  plan.about(l10n),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestRow extends StatelessWidget {
  const _SuggestRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(NexRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('modules-suggest'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.md),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline, color: scheme.primary),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Text(
                  l10n.modulesSuggest,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left
                    : Icons.chevron_right,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
