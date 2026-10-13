import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';
import '../../widgets/nex_shelf.dart';
import '../../widgets/vault_open_builder.dart';
import '../tools_screen.dart' show nexToggleToolPin;
import 'tool_catalog.dart';

/// The Tools page's tools pinned to the top of the timeline, as cards among
/// the notes: each one in its own colour, with its own icon, two to a row.
///
/// A tap opens the tool — a private one asks for the fingerprint as it does
/// from the Tools page, and its card shows nothing but its name. A hold takes
/// it off again. Nothing here when nothing is pinned.
class PinnedTools extends StatelessWidget {
  const PinnedTools({
    super.key,
    required this.services,
    required this.preferences,
    this.hidden = false,
  });

  final NexServices services;
  final NexPreferences preferences;

  /// In a search or a filtered list: nothing, without leaving the list.
  final bool hidden;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) {
      final tools = hidden
          ? const <NexTool>[]
          : nexPinnedTools(
              context,
              services: services,
              preferences: preferences,
            );
      final l = AppLocalizations.of(context);
      return AnimatedSize(
        duration: NexMotion.of(context, NexMotion.standard),
        curve: NexMotion.curve,
        alignment: Alignment.topCenter,
        child: tools.isEmpty
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.fromLTRB(
                  NexSpacing.md,
                  NexSpacing.xs,
                  NexSpacing.md,
                  NexSpacing.sm,
                ),
                child: nexShelfPairs([
                  for (final tool in tools)
                    VaultOpenBuilder(
                      key: ValueKey('pinned-tool-${tool.id}'),
                      builder: (context, open) => NexShelfTile(
                        compact: true,
                        title: tool.title,
                        subtitle: tool.subtitle,
                        icon: tool.icon,
                        hue: tool.hue,
                        badge: tool.locked ? nexLockBadge(open: open) : null,
                        onTap: () => unawaited(tool.push(context)),
                        onLongPress: () => unawaited(
                          nexToggleToolPin(context, preferences, tool),
                        ),
                        longPressLabel: l.unpinFromHome,
                      ),
                    ),
                ]),
              ),
      );
    },
  );
}
