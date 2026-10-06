import '../widgets/feature_label.dart';
import 'password_generator_screen.dart';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import 'cycle_screen.dart';
import '../platform/vault_store.dart';
import 'scheduled_screen.dart';
import 'vault_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key, this.services, this.preferences});

  /// Needed for the scheduled notes and «Cycle»; without them (an
  /// accessibility audit of the vault tiles alone) those tiles are left out.
  final NexServices? services;
  final NexPreferences? preferences;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.toolsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              l.toolsPrivateHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            // Two to a row: four tools fit on one screen with room to spare,
            // where the old full-width panels needed a scroll to reach the
            // last one.
            _pairs([
              _ToolTile(
                kind: VaultKind.password,
                title: l.vaultPasswords,
                subtitle: l.vaultPasswordsHint,
                icon: Icons.key_rounded,
              ),
              _ToolTile(
                kind: VaultKind.card,
                title: l.vaultCards,
                subtitle: l.vaultCardsHint,
                icon: Icons.credit_card_rounded,
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
              ),
              _ToolTile(
                title: l.vaultGenerator,
                subtitle: nexLabel(
                  context,
                  'Create and copy a strong password',
                  'ساخت و کپی رمز قوی',
                ),
                icon: Icons.casino_outlined,
                destination: const PasswordGeneratorScreen(),
              ),
            ]),
            if (services case final services?) ...[
              const SizedBox(height: 12),
              _pairs([
                if (preferences case final preferences?
                    when preferences.cycleEnabled)
                  _ToolTile(
                    title: l.cycleTitle,
                    subtitle: l.cycleSubtitle,
                    icon: Icons.water_drop_outlined,
                    destination: CycleScreen(
                      services: services,
                      preferences: preferences,
                    ),
                  ),
                _ToolTile(
                  title: l.scheduledTitle,
                  subtitle: l.scheduledSubtitle,
                  icon: Icons.schedule_send_outlined,
                  destination: ScheduledScreen(services: services),
                ),
              ]),
            ],
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
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

/// Tiles two to a row, each row as tall as its taller tile, so a large text
/// size grows the rows instead of clipping them the way a fixed-ratio grid
/// would.
Widget _pairs(List<Widget> tiles) => Column(
  children: [
    for (var i = 0; i < tiles.length; i += 2)
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < tiles.length
                    ? tiles[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
  ],
);

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    this.kind,
    this.destination,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final VaultKind? kind;
  final Widget? destination;
  final String title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          NexPageRoute<void>(
            builder: (_) => destination ?? VaultScreen(kind: kind!),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 22, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
