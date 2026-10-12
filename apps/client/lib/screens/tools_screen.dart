import '../widgets/feature_label.dart';
import '../widgets/nex_shelf.dart';
import 'password_generator_screen.dart';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../modules/module_registry.dart';
import 'modules_screen.dart';
import '../platform/vault_store.dart';
import 'scheduled_screen.dart';
import 'vault_screen.dart';

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
    final everyday = <Widget>[
      if (services case final services?) ...[
        _ToolTile(
          title: l.scheduledTitle,
          subtitle: l.scheduledSubtitle,
          icon: Icons.schedule_send_outlined,
          hue: NexHue.sky,
          destination: ScheduledScreen(services: services),
        ),
      ],
      _ToolTile(
        title: l.vaultGenerator,
        subtitle: nexLabel(
          context,
          'Create and copy a strong password',
          'ساخت و کپی رمز قوی',
        ),
        icon: Icons.casino_outlined,
        hue: NexHue.slate,
        destination: const PasswordGeneratorScreen(),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.toolsTitle)),
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
              _ToolTile(
                kind: VaultKind.password,
                title: l.vaultPasswords,
                subtitle: l.vaultPasswordsHint,
                icon: Icons.key_rounded,
                hue: NexHue.amber,
                locked: true,
              ),
              _ToolTile(
                kind: VaultKind.card,
                title: l.vaultCards,
                subtitle: l.vaultCardsHint,
                icon: Icons.credit_card_rounded,
                hue: NexHue.teal,
                locked: true,
              ),
              _ToolTile(
                kind: VaultKind.message,
                title: nexLabel(
                  context,
                  'Private saved messages',
                  'پیام‌های ذخیره‌شدهٔ خصوصی',
                ),
                subtitle: nexLabel(
                  context,
                  'A private space for your words',
                  'فضایی خصوصی برای متن‌های شما',
                ),
                icon: Icons.chat_bubble_outline,
                hue: NexHue.violet,
                locked: true,
              ),
            ]),
            const SizedBox(height: NexSpacing.lg),
            NexShelfHeading(
              icon: Icons.grid_view_rounded,
              title: l.toolsSectionEveryday,
            ),
            const SizedBox(height: NexSpacing.sm),
            nexShelfPairs(everyday),
            // The modules that are added, and the way to add more — see
            // `docs/17-modules.md`. Rebuilt from the preferences, so a module
            // added or removed on its page is here, or gone, on the way back.
            if ((services, preferences) case (
              final services?,
              final preferences?,
            )) ...[
              const SizedBox(height: NexSpacing.lg),
              NexShelfHeading(
                icon: Icons.extension_outlined,
                title: l.modulesTitle,
              ),
              const SizedBox(height: NexSpacing.sm),
              ListenableBuilder(
                listenable: preferences,
                builder: (context, _) => nexShelfPairs([
                  for (final module in nexModulesOn(preferences))
                    _ToolTile(
                      key: ValueKey('tools-module-${module.id}'),
                      title: module.title(l),
                      subtitle: module.tagline(l),
                      icon: module.icon,
                      hue: module.hue,
                      destination: module.open(
                        services: services,
                        preferences: preferences,
                      ),
                    ),
                  _ToolTile(
                    key: const ValueKey('tools-modules'),
                    title: l.modulesManage,
                    subtitle: l.modulesManageHint,
                    icon: Icons.extension_outlined,
                    hue: NexHue.violet,
                    destination: ModulesScreen(
                      services: services,
                      preferences: preferences,
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
  const _ToolTile({
    super.key,
    this.kind,
    this.destination,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.hue,
    this.locked = false,
  });
  final VaultKind? kind;
  final Widget? destination;
  final String title, subtitle;
  final IconData icon;
  final NexHue hue;
  final bool locked;

  @override
  Widget build(BuildContext context) => NexShelfTile(
    title: title,
    subtitle: subtitle,
    icon: icon,
    hue: hue,
    badge: locked ? Icons.lock_rounded : null,
    onTap: () => Navigator.push(
      context,
      NexPageRoute<void>(
        builder: (_) => destination ?? VaultScreen(kind: kind!),
      ),
    ),
  );
}
