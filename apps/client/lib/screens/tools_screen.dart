import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_shelf.dart';
import '../widgets/vault_open_builder.dart';
import '../modules/module_rollout.dart' show nexDesktopPlatform;
import 'module_settings_screen.dart';
import 'modules_screen.dart';
import 'tools/tool_catalog.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key, this.services, this.preferences});

  /// Needed for the scheduled notes and the modules; without them (an
  /// accessibility audit of the vault tiles alone) those tiles are left out.
  final NexServices? services;
  final NexPreferences? preferences;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preferences = this.preferences;
    // A hold pins a tool to the top of the timeline, or takes it off, with
    // the colour and icon it has here.
    Widget tile(NexTool tool) => preferences == null
        ? _ToolTile(tool: tool)
        : ListenableBuilder(
            listenable: preferences,
            builder: (context, _) => _ToolTile(
              tool: tool,
              pinned: preferences.isToolPinned(tool.id),
              onLongPress: () =>
                  unawaited(nexToggleToolPin(context, preferences, tool)),
            ),
          );
    return Scaffold(
      appBar: NexAppBar(title: Text(l.toolsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.xs,
            NexSpacing.md,
            NexSpacing.lg,
          ),
          children: [
            // Two shelves: what is behind the lock, and what is not. The
            // lock is the one thing that changes how a tool behaves, so it
            // is the line the page is divided on.
            NexShelfHeading(
              icon: Icons.lock_outline,
              title: l.toolsSectionPrivate,
              note: l.toolsPrivateHint,
            ),
            const SizedBox(height: NexSpacing.sm),
            nexShelfPairs([
              for (final tool in nexPrivateTools(
                context,
                biometricOnly: preferences?.appLockBiometricOnly ?? false,
              ))
                tile(tool),
            ]),
            // The modules that are added, and the way to add more — see
            // `docs/17-modules.md`. Rebuilt from the preferences, so a module
            // added or removed on its page is here, or gone, on the way back.
            if (!nexDesktopPlatform)
              if ((services, preferences) case (
                final services?,
                final preferences?,
              )) ...[
                const SizedBox(height: NexSpacing.lg),
                // The password generator lived in an "everyday" shelf here
                // until 2.8.1; it is the Security toolbox's now, and the
                // shelf, with nothing left on it, went with it. The hold-to-
                // pin hint it carried moves to the modules.
                NexShelfHeading(
                  icon: Icons.extension_outlined,
                  title: l.modulesTitle,
                  note: l.toolsPinHint,
                  // Their order and their pins, in one place (2.8.3).
                  trailing: IconButton(
                    key: const ValueKey('tools-arrange'),
                    tooltip: l.moduleSettingsTip,
                    icon: const Icon(Icons.tune),
                    onPressed: () => Navigator.push(
                      context,
                      NexPageRoute<void>(
                        builder: (_) => ModuleSettingsScreen(
                          services: services,
                          preferences: preferences,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: NexSpacing.sm),
                ListenableBuilder(
                  listenable: preferences,
                  builder: (context, _) => nexShelfPairs([
                    for (final tool in nexModuleTools(
                      context,
                      services: services,
                      preferences: preferences,
                    ))
                      KeyedSubtree(
                        key: ValueKey(
                          'tools-${tool.id.replaceFirst('.', '-')}',
                        ),
                        child: tile(tool),
                      ),
                    NexShelfTile(
                      key: const ValueKey('tools-modules'),
                      title: l.modulesManage,
                      subtitle: l.modulesManageHint,
                      icon: Icons.extension_outlined,
                      hue: NexHue.violet,
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
                  ]),
                ),
              ],
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Text(
                    l.vaultPrivacyHint,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool, this.pinned = false, this.onLongPress});

  final NexTool tool;
  final bool pinned;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget tile({IconData? badge}) => NexShelfTile(
      key: ValueKey('tool-${tool.id}'),
      title: tool.title,
      subtitle: tool.subtitle,
      icon: tool.icon,
      hue: tool.hue,
      badge: badge,
      pinned: pinned,
      onTap: () => unawaited(tool.push(context)),
      onLongPress: onLongPress,
      longPressLabel: onLongPress == null
          ? null
          : (pinned ? l.unpinFromHome : l.pinToHome),
    );
    if (!tool.locked) return tile();
    return VaultOpenBuilder(
      builder: (context, open) => tile(badge: nexLockBadge(open: open)),
    );
  }
}

/// Pins [tool] to the home screen or takes it off, and says which, with a
/// way back.
Future<void> nexToggleToolPin(
  BuildContext context,
  NexPreferences preferences,
  NexTool tool,
) async {
  final l = AppLocalizations.of(context);
  unawaited(HapticFeedback.selectionClick());
  final pinned = await preferences.togglePinnedTool(tool.id);
  if (!context.mounted) return;
  nexShowBanner(
    context,
    message: pinned ? l.toolPinned : l.toolUnpinned,
    actionLabel: l.undo,
    onAction: () => unawaited(preferences.togglePinnedTool(tool.id)),
  );
}
