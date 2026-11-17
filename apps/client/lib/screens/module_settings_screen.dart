import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/nex_shelf.dart';
import 'tools/tool_catalog.dart';
import 'tools_screen.dart' show nexToggleToolPin;

/// Arranging tools and modules, in one place (2.8.3).
///
/// Pinning used to be a hold on a tile, which most people never found, and
/// the pins and the modules kept the order they happened to be added in.
/// Here every tool has its pin in plain sight, what is on the home screen is
/// put in order by dragging, and so are the modules on the Tools page.
class ModuleSettingsScreen extends StatelessWidget {
  const ModuleSettingsScreen({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: NexAppBar(title: Text(l.moduleSettingsTitle)),
      body: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) {
          final private = nexPrivateTools(
            context,
            biometricOnly: preferences.appLockBiometricOnly,
          );
          final modules = nexModuleTools(
            context,
            services: services,
            preferences: preferences,
          );
          final pinned = nexPinnedTools(
            context,
            services: services,
            preferences: preferences,
          );
          final quiet = theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          );
          Widget pin(NexTool tool) => _PinButton(
            pinned: preferences.isToolPinned(tool.id),
            onPressed: () =>
                unawaited(nexToggleToolPin(context, preferences, tool)),
          );
          return ListView(
            padding: EdgeInsets.fromLTRB(
              NexSpacing.md,
              NexSpacing.sm,
              NexSpacing.md,
              NexSpacing.lg + nexBottomInset(context),
            ),
            children: [
              NexShelfHeading(
                icon: Icons.push_pin_outlined,
                title: l.moduleSettingsHome,
                note: pinned.isEmpty ? null : l.moduleSettingsHomeHint,
              ),
              const SizedBox(height: NexSpacing.sm),
              if (pinned.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: NexSpacing.md),
                  child: Text(l.moduleSettingsHomeEmpty, style: quiet),
                )
              else
                _Arranged(
                  listKey: 'arrange-home',
                  tools: pinned,
                  trailing: pin,
                  onReorder: (ids) =>
                      unawaited(preferences.setPinnedTools(ids)),
                ),
              const SizedBox(height: NexSpacing.lg),
              NexShelfHeading(
                icon: Icons.extension_outlined,
                title: l.moduleSettingsYours,
                note: modules.length < 2 ? null : l.moduleSettingsYoursHint,
              ),
              const SizedBox(height: NexSpacing.sm),
              if (modules.isEmpty)
                Text(l.moduleSettingsNoModules, style: quiet)
              else
                _Arranged(
                  listKey: 'arrange-modules',
                  tools: modules,
                  trailing: pin,
                  onReorder: (ids) => unawaited(
                    preferences.setModuleOrder([
                      for (final id in ids) id.replaceFirst('module.', ''),
                    ]),
                  ),
                ),
              const SizedBox(height: NexSpacing.lg),
              NexShelfHeading(
                icon: Icons.lock_outline,
                title: l.toolsSectionPrivate,
              ),
              const SizedBox(height: NexSpacing.sm),
              for (final (i, tool) in private.indexed)
                NexGroupedRow(
                  key: ValueKey('arrange-private-${tool.id}'),
                  index: i,
                  count: private.length,
                  child: _ToolRow(tool: tool, trailing: pin(tool)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Tools in an order the person sets by dragging.
class _Arranged extends StatelessWidget {
  const _Arranged({
    required this.listKey,
    required this.tools,
    required this.trailing,
    required this.onReorder,
  });

  final String listKey;
  final List<NexTool> tools;
  final Widget Function(NexTool tool) trailing;
  final ValueChanged<List<String>> onReorder;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ReorderableListView(
      key: ValueKey(listKey),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) => Material(
        type: MaterialType.transparency,
        child: ScaleTransition(
          scale: animation.drive(Tween(begin: 1, end: 1.02)),
          child: child,
        ),
      ),
      onReorderItem: (from, to) {
        final ids = [for (final t in tools) t.id];
        ids.insert(to, ids.removeAt(from));
        onReorder(ids);
      },
      children: [
        for (final (i, tool) in tools.indexed)
          NexGroupedRow(
            key: ValueKey('$listKey-${tool.id}'),
            index: i,
            count: tools.length,
            child: _ToolRow(
              tool: tool,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  trailing(tool),
                  ReorderableDragStartListener(
                    index: i,
                    child: Tooltip(
                      message: l.moduleDragTip,
                      child: const SizedBox(
                        width: 44,
                        height: 48,
                        child: Icon(Icons.drag_indicator),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool, required this.trailing});

  final NexTool tool;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => unawaited(tool.push(context)),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: NexSpacing.md,
          top: NexSpacing.xs,
          bottom: NexSpacing.xs,
        ),
        child: Row(
          children: [
            NexIconTile(tool.icon, color: tool.hue.of(theme.brightness)),
            const SizedBox(width: NexSpacing.md),
            Expanded(
              child: Text(
                tool.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({required this.pinned, required this.onPressed});

  final bool pinned;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: pinned ? l.unpinFromHome : l.pinToHome,
      isSelected: pinned,
      onPressed: onPressed,
      icon: Icon(Icons.push_pin_outlined, color: scheme.onSurfaceVariant),
      selectedIcon: Icon(Icons.push_pin, color: scheme.primary),
    );
  }
}
