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
    final everyday = <Widget>[
      if (services case final services?) ...[
        if (preferences case final preferences? when preferences.cycleEnabled)
          _ToolTile(
            title: l.cycleTitle,
            subtitle: l.cycleSubtitle,
            icon: Icons.water_drop_outlined,
            hue: _Hue.rose,
            destination: CycleScreen(
              services: services,
              preferences: preferences,
            ),
          ),
        _ToolTile(
          title: l.scheduledTitle,
          subtitle: l.scheduledSubtitle,
          icon: Icons.schedule_send_outlined,
          hue: _Hue.sky,
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
        hue: _Hue.slate,
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
            _ShelfHeading(
              icon: Icons.lock_outline,
              title: l.toolsSectionPrivate,
              note: l.toolsPrivateHint,
            ),
            const SizedBox(height: NexSpacing.sm),
            _pairs([
              _ToolTile(
                kind: VaultKind.password,
                title: l.vaultPasswords,
                subtitle: l.vaultPasswordsHint,
                icon: Icons.key_rounded,
                hue: _Hue.amber,
                locked: true,
              ),
              _ToolTile(
                kind: VaultKind.card,
                title: l.vaultCards,
                subtitle: l.vaultCardsHint,
                icon: Icons.credit_card_rounded,
                hue: _Hue.teal,
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
                hue: _Hue.violet,
                locked: true,
              ),
            ]),
            const SizedBox(height: NexSpacing.lg),
            _ShelfHeading(
              icon: Icons.grid_view_rounded,
              title: l.toolsSectionEveryday,
            ),
            const SizedBox(height: NexSpacing.sm),
            _pairs(everyday),
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

/// A shelf's name, with its icon and, for the private one, the line that
/// says what keeps it apart.
class _ShelfHeading extends StatelessWidget {
  const _ShelfHeading({required this.icon, required this.title, this.note});

  final IconData icon;
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final note = this.note;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: NexSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: NexSpacing.xs + 2),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Each tool's own colour, so the shelf reads at a glance — the key is
/// amber, the cards teal — rather than as a row of identical boxes.
enum _Hue {
  amber(Color(0xFFB7791F), Color(0xFFF2C46D)),
  teal(Color(0xFF1F8A7A), Color(0xFF6FD3C2)),
  violet(Color(0xFF6B4FC8), Color(0xFFB7A4F4)),
  rose(Color(0xFFC2456A), Color(0xFFF29AB3)),
  sky(Color(0xFF2370C2), Color(0xFF8CC0F2)),
  slate(Color(0xFF55606E), Color(0xFFB4BDC8));

  const _Hue(this.light, this.dark);

  final Color light;
  final Color dark;

  Color of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
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
              // An odd one out takes the whole row rather than leaving a
              // hole beside it.
              if (i + 1 < tiles.length) ...[
                const SizedBox(width: 12),
                Expanded(child: tiles[i + 1]),
              ],
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
    required this.hue,
    this.locked = false,
  });
  final VaultKind? kind;
  final Widget? destination;
  final String title, subtitle;
  final IconData icon;
  final _Hue hue;

  /// Behind the shared unlock: a small lock in the corner says so.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = hue.of(theme.brightness);
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          NexPageRoute<void>(
            builder: (_) => destination ?? VaultScreen(kind: kind!),
          ),
        ),
        child: Ink(
          // A wash of the tool's colour from its corner, fading out
          // before it reaches the words.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [
                color.withValues(alpha: 0.16),
                color.withValues(alpha: 0.02),
              ],
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: theme.brightness == Brightness.dark
                          ? Colors.black87
                          : Colors.white,
                    ),
                  ),
                  const Spacer(),
                  if (locked)
                    Icon(
                      Icons.lock_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
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
