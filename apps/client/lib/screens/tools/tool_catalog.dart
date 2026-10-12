import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../modules/module_registry.dart';
import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';
import '../../platform/vault_store.dart';
import '../../widgets/nex_shelf.dart';
import '../password_generator_screen.dart';
import '../scheduled_screen.dart';
import '../vault_screen.dart';

/// One thing on the Tools page: what it is called, how it looks, and where it
/// leads. The Tools page and the tools pinned to the home screen are drawn
/// from the same list, so a pinned tool has the colour and icon it has there.
class NexTool {
  const NexTool({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.hue,
    required this.open,
    this.locked = false,
  });

  /// Stable: what a pin is stored as.
  final String id;
  final String title, subtitle;
  final IconData icon;
  final NexHue hue;

  /// Behind the fingerprint. Its screen asks for it, wherever it is opened
  /// from, and its pinned card shows only its name.
  final bool locked;

  final WidgetBuilder open;

  Future<void> push(BuildContext context) =>
      Navigator.push(context, NexPageRoute<void>(builder: open));
}

/// The private tools, behind the lock.
List<NexTool> nexPrivateTools(BuildContext context) {
  final l = AppLocalizations.of(context);
  return [
    NexTool(
      id: 'vault.password',
      title: l.vaultPasswords,
      subtitle: l.vaultPasswordsHint,
      icon: Icons.key_rounded,
      hue: NexHue.amber,
      locked: true,
      open: (_) => const VaultScreen(kind: VaultKind.password),
    ),
    NexTool(
      id: 'vault.card',
      title: l.vaultCards,
      subtitle: l.vaultCardsHint,
      icon: Icons.credit_card_rounded,
      hue: NexHue.teal,
      locked: true,
      open: (_) => const VaultScreen(kind: VaultKind.card),
    ),
    NexTool(
      id: 'vault.message',
      title: l.toolsMessages,
      subtitle: l.toolsMessagesHint,
      icon: Icons.chat_bubble_outline,
      hue: NexHue.violet,
      locked: true,
      open: (_) => const VaultScreen(kind: VaultKind.message),
    ),
  ];
}

/// The everyday tools. Scheduled notes need [services].
List<NexTool> nexEverydayTools(BuildContext context, {NexServices? services}) {
  final l = AppLocalizations.of(context);
  return [
    if (services case final services?)
      NexTool(
        id: 'scheduled',
        title: l.scheduledTitle,
        subtitle: l.scheduledSubtitle,
        icon: Icons.schedule_send_outlined,
        hue: NexHue.sky,
        open: (_) => ScheduledScreen(services: services),
      ),
    NexTool(
      id: 'generator',
      title: l.vaultGenerator,
      subtitle: l.toolsGeneratorHint,
      icon: Icons.casino_outlined,
      hue: NexHue.slate,
      open: (_) => const PasswordGeneratorScreen(),
    ),
  ];
}

/// The modules that are added.
List<NexTool> nexModuleTools(
  BuildContext context, {
  required NexServices services,
  required NexPreferences preferences,
}) {
  final l = AppLocalizations.of(context);
  return [
    for (final module in nexModulesOn(preferences))
      NexTool(
        id: 'module.${module.id}',
        title: module.title(l),
        subtitle: module.tagline(l),
        icon: module.icon,
        hue: module.hue,
        open: (_) => module.open(services: services, preferences: preferences),
      ),
  ];
}

/// The tools pinned to the home screen, in the order they were pinned. A pin
/// whose tool is gone — a module removed — is left out rather than drawn as
/// a card that leads nowhere.
List<NexTool> nexPinnedTools(
  BuildContext context, {
  required NexServices services,
  required NexPreferences preferences,
}) {
  final pins = preferences.pinnedTools;
  if (pins.isEmpty) return const [];
  final all = {
    for (final tool in [
      ...nexPrivateTools(context),
      ...nexEverydayTools(context, services: services),
      ...nexModuleTools(context, services: services, preferences: preferences),
    ])
      tool.id: tool,
  };
  return [
    for (final id in pins)
      if (all[id] case final tool?) tool,
  ];
}
