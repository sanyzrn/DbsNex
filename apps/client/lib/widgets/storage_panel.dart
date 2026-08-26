import 'package:flutter/material.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';

/// What the library is actually made of.
///
/// The row this replaces said "Storage — 41 MB" and stopped. That is not an
/// answer to the only question anyone opens a storage screen with, which is
/// *what should I delete*: one number cannot be acted on, and this one was
/// wrong besides — it counted the database, the media and the backups, and
/// left out the offline model, which on an install that has one is larger
/// than all three together by an order of magnitude.
///
/// So: the total, a bar, and the parts. The bar is the shape every storage
/// screen worth copying uses — iOS and One UI both — because a proportion is
/// read from a length far faster than from five numbers, and the numbers are
/// underneath for when the proportion is not enough.
///
/// The colours are fixed rather than derived from the accent. They have to
/// stay apart from each other to mean anything, and five hues generated from
/// one seed are five shades of the same thing.
class StoragePanel extends StatelessWidget {
  const StoragePanel({super.key, required this.snapshot});

  final StorageSnapshot snapshot;

  /// A segment under a hair's width of the bar is not readable as a colour,
  /// and a row for it reads as clutter. Its bytes are still in the total.
  static const _minimumShare = 0.005;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final parts = <(String, int, Color)>[
      (l10n.storageModels, snapshot.models, const Color(0xFF9B6DFF)),
      (l10n.storageImages, snapshot.images, const Color(0xFF4C8DFF)),
      (l10n.storageAudio, snapshot.audio, const Color(0xFF34B27B)),
      (l10n.storageBackups, snapshot.backups, const Color(0xFFFF9F45)),
      (l10n.storageNotes, snapshot.database, const Color(0xFFE0559B)),
      (l10n.storageOther, snapshot.otherMedia, const Color(0xFF8A8F98)),
    ];
    final total = snapshot.total;
    final shown = [
      for (final part in parts)
        if (part.$2 > 0 && part.$2 / (total == 0 ? 1 : total) >= _minimumShare)
          part,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(l10n.storage, style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                nexFormatBytes(total),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
          child: _Bar(
            parts: shown,
            total: total,
            empty: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
            child: Text(
              l10n.storageEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final (label, bytes, color) in shown)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NexSpacing.lg,
                vertical: NexSpacing.xs,
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: Text(label, style: theme.textTheme.bodyMedium),
                  ),
                  Text(
                    nexFormatBytes(bytes),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// The proportions, as one rounded bar.
///
/// Flex rather than measured widths: the segments then divide whatever width
/// the screen has without this having to know it, and a rounded clip on the
/// outside means the ends are shaped and the joins between segments are not —
/// which is what makes it read as one bar rather than a row of pills.
class _Bar extends StatelessWidget {
  const _Bar({required this.parts, required this.total, required this.empty});

  final List<(String, int, Color)> parts;
  final int total;
  final Color empty;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(NexRadius.xs),
      child: SizedBox(
        height: 10,
        child: parts.isEmpty
            ? ColoredBox(color: empty)
            : Row(
                children: [
                  for (final (_, bytes, color) in parts)
                    Expanded(
                      // Weighted by bytes. Integer flex, so a part under a
                      // thousandth of the bar still gets one unit rather than
                      // collapsing the row's arithmetic to zero.
                      flex: bytes.clamp(1, total == 0 ? 1 : total),
                      child: ColoredBox(color: color),
                    ),
                ],
              ),
      ),
    );
  }
}
