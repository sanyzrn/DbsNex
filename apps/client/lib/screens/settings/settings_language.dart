part of '../settings_sheet.dart';

/// A language as its own letters, with the way it reads: the circle every
/// choice card carries, and a small arrow at its foot for the direction the
/// whole interface turns to.
class _ScriptBadge extends StatelessWidget {
  const _ScriptBadge({this.sample, this.icon, this.rtl});

  final String? sample;
  final IconData? icon;

  /// Null for the system choice, which follows the phone either way.
  final bool? rtl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rtl = this.rtl;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: NexScriptSample(sample: sample, icon: icon),
          ),
          if (rtl != null)
            PositionedDirectional(
              bottom: -2,
              end: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                // East and west, not forward and back: those two mirror
                // themselves under a right-to-left interface, and this
                // arrow is about the language, not the interface.
                child: Icon(
                  rtl ? Icons.west : Icons.east,
                  size: 12,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A calendar as a leaf torn from it: today's day, under its month in that
/// calendar — so the choice is between two dates you can read, not two names.
class _CalendarLeaf extends StatelessWidget {
  const _CalendarLeaf({required this.solar});

  final bool solar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final now = DateTime.now();
    final String month;
    final int day;
    if (solar) {
      final date = nexPersianDate(now);
      month = (persian
          ? nexPersianMonthNames
          : nexPersianMonthNamesLatin)[date.month - 1];
      day = date.day;
    } else {
      month = _format(DateFormat.MMM, persian, now);
      day = now.day;
    }
    return Container(
      width: 52,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(NexRadius.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: scheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              month,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              nexDigits('$day', persian: persian),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two choices above, together, as the timeline will show them: a day
/// heading in the chosen calendar over a note written in the chosen language.
class _LanguagePreview extends StatelessWidget {
  const _LanguagePreview({required this.solar});

  final bool solar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final now = DateTime.now();
    final String date;
    if (solar) {
      final p = nexPersianDate(now);
      final month = (persian
          ? nexPersianMonthNames
          : nexPersianMonthNamesLatin)[p.month - 1];
      date = nexDigits('${p.day} $month ${p.year}', persian: persian);
    } else {
      date = nexDigits(
        _format(DateFormat.yMMMd, persian, now),
        persian: persian,
      );
    }
    final time = nexDigits(
      TimeOfDay.fromDateTime(now).format(context),
      persian: persian,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        NexSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _IconTile(Icons.visibility_outlined),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Text(
                  l10n.languagePreviewTitle,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.all(NexSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(NexRadius.md),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Two pieces, not one string joined by a middle dot: in
                  // Persian text a "·" beside digits reads as a zero.
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: l10n.timelineGroupToday,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: '   '),
                        TextSpan(text: date),
                      ],
                    ),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(NexSpacing.sm + 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(NexRadius.md),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            l10n.languagePreviewNote,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: NexSpacing.sm),
                        Text(
                          time,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [pattern] in Persian when the interface is, falling back to English where
/// Persian date names were never loaded — a bare test app, for one.
String _format(
  DateFormat Function([String? locale]) pattern,
  bool persian,
  DateTime when,
) {
  if (persian) {
    try {
      return pattern('fa').format(when);
    } catch (_) {}
  }
  return pattern('en').format(when);
}
