import '../widgets/feature_label.dart';
import 'password_generator_screen.dart';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';
import '../platform/vault_store.dart';
import 'vault_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.toolsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.space_dashboard_outlined,
              size: 44,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(l.toolsSubtitle, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              l.toolsPrivateHint,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            _ToolTile(
              kind: VaultKind.password,
              title: l.vaultPasswords,
              subtitle: l.vaultPasswordsHint,
              icon: Icons.key_rounded,
            ),
            const SizedBox(height: 16),
            _ToolTile(
              kind: VaultKind.card,
              title: l.vaultCards,
              subtitle: l.vaultCardsHint,
              icon: Icons.credit_card_rounded,
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
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
        borderRadius: BorderRadius.circular(28),
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      icon,
                      size: 30,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    textDirection: Directionality.of(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
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
