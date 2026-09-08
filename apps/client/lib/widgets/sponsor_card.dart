import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/sponsor.dart';

/// The one card in the timeline that is not a note.
///
/// Built to the note card's geometry — same insets, same height, same corner
/// — so it sits in the stream rather than on top of it, and coloured so that
/// nobody has to read it to know it is not something they wrote. Those two
/// things are in tension on purpose: it belongs to the list, and it is
/// honest about not being part of the library.
///
/// It carries a dismiss control, and the dismissal is permanent for that
/// card. A card someone has said no to and which comes back is the thing
/// that makes people uninstall.
class SponsorCard extends StatelessWidget {
  const SponsorCard({
    super.key,
    required this.sponsor,
    required this.onOpen,
    required this.onDismiss,
  });

  final NexSponsor sponsor;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The card's own colour, falling back to the accent — a card whose author
    // did not choose one is still allowed to be coloured.
    final tint = nexParseTagColor(sponsor.color) ?? theme.colorScheme.primary;
    // Tinted rather than filled: a saturated block the size of a card, three
    // times down a list of quiet ones, is a thing people learn to scroll past
    // without reading. The border does the work of saying "different".
    final ground = Color.alphaBlend(
      tint.withValues(alpha: theme.brightness == Brightness.dark ? 0.18 : 0.10),
      theme.colorScheme.surface,
    );
    final body = sponsor.body;
    return Padding(
      padding: nexCardInsets,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: nexCardHeightFor(context)),
        child: Material(
          color: ground,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          child: InkWell(
            onTap: sponsor.url == null ? null : onOpen,
            borderRadius: BorderRadius.circular(NexRadius.lg),
            child: Container(
              padding: const EdgeInsets.all(NexSpacing.cardInset),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(NexRadius.lg),
                border: Border.all(color: tint.withValues(alpha: 0.45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: nexCardLeadingSize,
                    height: nexCardLeadingSize,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(NexRadius.md),
                    ),
                    child: Icon(Icons.campaign_outlined, color: tint),
                  ),
                  const SizedBox(width: NexSpacing.contentGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Says what it is, in small type, above the words
                        // somebody paid for. Not a disclosure buried at the
                        // bottom — the label is the first thing read.
                        Text(
                          l10n.sponsorLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sponsor.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: nexDirectionOf(sponsor.title),
                          style: theme.textTheme.titleSmall,
                        ),
                        if (body != null && body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: nexDirectionOf(body),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // A real tap target, not a 16dp cross. Putting a card in
                  // somebody's list obliges the app to make it easy to take
                  // back out.
                  IconButton(
                    tooltip: l10n.sponsorDismiss,
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
