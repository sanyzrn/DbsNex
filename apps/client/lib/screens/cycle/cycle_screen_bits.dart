part of '../cycle_screen.dart';

// The small pieces of the Cycle screen. Split out of cycle_screen.dart
// (REL-10).

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: CycleCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(
          horizontal: NexSpacing.sm + 4,
          vertical: NexSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A greeting by the hour and a line for where the cycle is, so the page
/// opens on a person, not on a number.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.whisper});

  final String whisper;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final hello = hour >= 5 && hour < 12
        ? l10n.cycleGreetingMorning
        : hour >= 12 && hour < 17
        ? l10n.cycleGreetingAfternoon
        : hour >= 17 && hour < 21
        ? l10n.cycleGreetingEvening
        : l10n.cycleGreetingNight;
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.xs, bottom: NexSpacing.md),
      child: Column(
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => cycleBloom(
              theme.brightness,
            ).createShader(bounds, textDirection: Directionality.of(context)),
            child: Text(
              hello,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            whisper,
            key: const ValueKey('cycle-whisper'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small round of rose light holding an icon.
class _Bud extends StatelessWidget {
  const _Bud({required this.icon, this.size = 40});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final rose = cyclePeriodColor(brightness);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            rose.withValues(alpha: 0.26),
            cycleMauve(brightness).withValues(alpha: 0.10),
          ],
        ),
      ),
      child: Icon(icon, size: size * 0.5, color: rose),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.sm,
        vertical: NexSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
