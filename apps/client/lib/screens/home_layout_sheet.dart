import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/timeline_shelves.dart';
import 'tools/tool_catalog.dart';

/// What the home screen shows, and how it looks — one tap from the screen it
/// changes (2.3.0).
///
/// Every piece above the notes is the app's idea rather than the reader's — a
/// greeting, a generated summary, a search field and a row of tags, on a
/// screen whose subject is the list underneath them. This is the answer to "I
/// just want my notes". Card size and text size sit here too, because they
/// are the two things people change while looking at the result, and the
/// Settings form for them is three taps and a page away.
///
/// Small on purpose: four tiles that light up when on, the tools that can
/// sit on the home screen as chips, a strip of three tiny cards to pick a
/// size from, and a row of four "A"s for the text.
///
/// The tools are here since 2.8.0. Pinning one used to be a hold on its tile
/// on the Tools page and nowhere else — a gesture nothing on the home screen
/// mentioned, for a row that is part of the home screen.
class HomeLayoutSheet extends StatefulWidget {
  const HomeLayoutSheet({super.key, required this.preferences, this.services});

  final NexPreferences preferences;

  /// Needed to offer the modules as pinned tools; without it (a test that
  /// builds the sheet alone) the section lists the tools that need none.
  final NexServices? services;

  @override
  State<HomeLayoutSheet> createState() => _HomeLayoutSheetState();
}

class _HomeLayoutSheetState extends State<HomeLayoutSheet> {
  static const _scales = [0.9, 1.0, 1.15, 1.3];

  Future<void> _then(Future<void> change) async {
    await change;
    if (mounted) setState(() {});
  }

  /// Everything that can be a tile on the home screen: the modules that are
  /// added first — they are the ones with something live to show — then the
  /// private tools.
  List<NexTool> _pinnable(BuildContext context) => [
    if (widget.services case final services?)
      ...nexModuleTools(
        context,
        services: services,
        preferences: widget.preferences,
      ),
    ...nexPrivateTools(
      context,
      biometricOnly: widget.preferences.appLockBiometricOnly,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prefs = widget.preferences;
    final label = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget toggle(
      String key,
      IconData icon,
      String text,
      bool value,
      Future<void> Function(bool) set,
    ) => _ToggleTile(
      key: ValueKey('layout-$key'),
      icon: icon,
      label: text,
      on: value,
      onTap: () => _then(set(!value)),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          NexSpacing.md,
          NexSpacing.md,
          NexSpacing.md,
          NexSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.layoutTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: NexSpacing.xs),
            Text(
              l10n.layoutSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            Text(l10n.layoutShowSection, style: label),
            const SizedBox(height: NexSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: toggle(
                    'greeting',
                    Icons.waving_hand_outlined,
                    l10n.layoutGreeting,
                    prefs.showGreeting,
                    prefs.setShowGreeting,
                  ),
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: toggle(
                    'summary',
                    Icons.auto_awesome_outlined,
                    l10n.layoutDaySummary,
                    prefs.showDaySummary,
                    prefs.setShowDaySummary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: toggle(
                    'search',
                    Icons.search,
                    l10n.layoutSearchField,
                    prefs.showSearchField,
                    prefs.setShowSearchField,
                  ),
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: toggle(
                    'tags',
                    Icons.sell_outlined,
                    l10n.layoutTagRow,
                    prefs.showTagRow,
                    prefs.setShowTagRow,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.lg),
            Text(l10n.layoutPinnedTools, style: label),
            const SizedBox(height: NexSpacing.xs),
            Text(
              l10n.layoutPinnedToolsHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            Wrap(
              spacing: NexSpacing.sm,
              runSpacing: NexSpacing.sm,
              children: [
                for (final tool in _pinnable(context))
                  _PinChip(
                    key: ValueKey('layout-pin-${tool.id}'),
                    tool: tool,
                    pinned: prefs.isToolPinned(tool.id),
                    onTap: () {
                      nexTick();
                      unawaited(_then(prefs.togglePinnedTool(tool.id)));
                    },
                  ),
              ],
            ),
            const SizedBox(height: NexSpacing.lg),
            Text(l10n.layoutLookSection, style: label),
            const SizedBox(height: NexSpacing.sm),
            Text(l10n.timelineView, style: theme.textTheme.bodyMedium),
            const SizedBox(height: NexSpacing.sm),
            Row(
              children: [
                for (final (i, grid) in const [false, true].indexed) ...[
                  if (i > 0) const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: _ToggleTile(
                      key: ValueKey('layout-view-${grid ? 'grid' : 'list'}'),
                      icon: grid
                          ? Icons.grid_view_rounded
                          : Icons.view_agenda_outlined,
                      label: grid
                          ? l10n.timelineViewGrid
                          : l10n.timelineViewList,
                      on: prefs.timelineGrid == grid,
                      onTap: () => _then(prefs.setTimelineGrid(grid)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: NexSpacing.md),
            Text(l10n.timelineArrange, style: theme.textTheme.bodyMedium),
            const SizedBox(height: NexSpacing.sm),
            Row(
              children: [
                for (final (i, by)
                    in NexTimelineArrangement.values.indexed) ...[
                  if (i > 0) const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: _ToggleTile(
                      key: ValueKey('layout-arrange-${by.name}'),
                      icon: switch (by) {
                        NexTimelineArrangement.time => Icons.schedule_rounded,
                        NexTimelineArrangement.type => Icons.category_outlined,
                        NexTimelineArrangement.tag => Icons.sell_outlined,
                      },
                      label: switch (by) {
                        NexTimelineArrangement.time => l10n.timelineArrangeTime,
                        NexTimelineArrangement.type => l10n.timelineArrangeType,
                        NexTimelineArrangement.tag => l10n.timelineArrangeTag,
                      },
                      on: prefs.timelineArrangement == by,
                      onTap: () => _then(prefs.setTimelineArrangement(by)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: NexSpacing.xs),
            Text(
              l10n.timelineArrangeHint(prefs.timelineArrangement.name),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            Text(l10n.cardDensity, style: theme.textTheme.bodyMedium),
            const SizedBox(height: NexSpacing.sm),
            Row(
              children: [
                for (final (i, density) in NexCardDensity.values.indexed) ...[
                  if (i > 0) const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: _DensityTile(
                      key: ValueKey('layout-density-${density.name}'),
                      density: density,
                      label: switch (density) {
                        NexCardDensity.compact => l10n.cardDensityCompact,
                        NexCardDensity.standard => l10n.cardDensityStandard,
                        NexCardDensity.readable => l10n.cardDensityReadable,
                      },
                      selected: prefs.cardDensity == density,
                      onTap: () => _then(prefs.setCardDensity(density)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: NexSpacing.md),
            Text(l10n.uiScale, style: theme.textTheme.bodyMedium),
            const SizedBox(height: NexSpacing.sm),
            _ScaleRow(
              scales: _scales,
              labels: [
                l10n.uiScaleSmall,
                l10n.uiScaleDefault,
                l10n.uiScaleLarge,
                l10n.uiScaleLarger,
              ],
              selected: prefs.uiScale,
              onSelect: (scale) => _then(prefs.setUiScale(scale)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One thing above the notes: lit when it is shown.
class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    super.key,
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      toggled: on,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          child: AnimatedContainer(
            duration: NexMotion.of(context, NexMotion.standard),
            curve: NexMotion.curve,
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.md,
              vertical: NexSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: on
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(NexRadius.lg),
              border: Border.all(
                color: on
                    ? scheme.primary.withValues(alpha: 0.5)
                    : scheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: on
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: on ? scheme.onPrimaryContainer : scheme.onSurface,
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: NexMotion.of(context, NexMotion.pop),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    on ? Icons.check_circle : Icons.circle_outlined,
                    key: ValueKey(on),
                    size: 18,
                    color: on ? scheme.primary : scheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tool that can be pinned to the home screen: its own mark and name, lit
/// in its own colour while it is pinned.
class _PinChip extends StatelessWidget {
  const _PinChip({
    super.key,
    required this.tool,
    required this.pinned,
    required this.onTap,
  });

  final NexTool tool;
  final bool pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = tool.hue.of(theme.brightness);
    return NexTappable(
      onTap: onTap,
      selected: pinned,
      semanticLabel: tool.title,
      shape: const StadiumBorder(),
      child: AnimatedContainer(
        duration: NexMotion.of(context, NexMotion.standard),
        curve: NexMotion.curve,
        padding: const EdgeInsetsDirectional.fromSTEB(
          NexSpacing.sm,
          NexSpacing.sm,
          NexSpacing.md - NexSpacing.xs,
          NexSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: pinned
              ? color.withValues(alpha: 0.16)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(NexRadius.pill),
          border: Border.all(
            color: pinned
                ? color.withValues(alpha: 0.7)
                : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: NexMotion.of(context, NexMotion.pop),
              switchInCurve: NexMotion.popCurve,
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                pinned ? Icons.push_pin_rounded : tool.icon,
                key: ValueKey(pinned),
                size: 18,
                color: pinned
                    ? nexReadableOn(
                        color,
                        Color.alphaBlend(
                          color.withValues(alpha: 0.16),
                          scheme.surface,
                        ),
                      )
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: NexSpacing.sm),
            Flexible(
              child: Text(
                tool.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card size, shown as a tiny card of that size rather than named only.
class _DensityTile extends StatelessWidget {
  const _DensityTile({
    super.key,
    required this.density,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final NexCardDensity density;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The preview card's lines and square scale with the real density.
    final lines = density.lines;
    final square = density.leading * 0.42;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          child: AnimatedContainer(
            duration: NexMotion.of(context, NexMotion.standard),
            curve: NexMotion.curve,
            padding: const EdgeInsets.all(NexSpacing.sm),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(NexRadius.lg),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Container(
                  height: 52,
                  padding: EdgeInsets.all(density.inset * 0.35),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(NexRadius.sm),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: square,
                        height: square,
                        // Round, as the mark on a real card is.
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < lines; i++)
                              Container(
                                height: 4,
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                width: i == lines - 1 ? 22 : 40,
                                decoration: BoxDecoration(
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: 0.35,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    NexRadius.xs / 2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NexSpacing.xs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Four "A"s, each a size bigger: the text size is picked by its look.
class _ScaleRow extends StatelessWidget {
  const _ScaleRow({
    required this.scales,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<double> scales;
  final List<String> labels;
  final double selected;
  final ValueChanged<double> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(NexSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(NexRadius.xl),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          for (final (i, scale) in scales.indexed)
            Expanded(
              child: Semantics(
                selected: (scale - selected).abs() < 0.01,
                button: true,
                label: labels[i],
                excludeSemantics: true,
                child: GestureDetector(
                  key: ValueKey('layout-scale-$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(scale),
                  child: AnimatedContainer(
                    duration: NexMotion.of(context, NexMotion.standard),
                    curve: NexMotion.curve,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (scale - selected).abs() < 0.01
                          ? scheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(NexRadius.xl),
                    ),
                    child: Text(
                      'A',
                      // Not scaled again by the text size it is choosing.
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 13.0 + i * 4,
                        fontWeight: FontWeight.w600,
                        color: (scale - selected).abs() < 0.01
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
