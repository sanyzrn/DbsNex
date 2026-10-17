import 'dart:io';

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
/// It carries a dismiss control when [onDismiss] is given. The timeline leaves
/// it out while [NexSponsorService.dismissible] is off.
class SponsorCard extends StatelessWidget {
  const SponsorCard({
    super.key,
    required this.sponsor,
    required this.onOpen,
    this.onDismiss,
    this.image,
  });

  final NexSponsor sponsor;

  /// The cached picture, when available. Missing or unreadable pictures
  /// fall back to the campaign's words.
  final File? image;
  final VoidCallback onOpen;
  final VoidCallback? onDismiss;

  // Always the standard card, whatever card size is chosen in Appearance.
  // The words and the banner picture are laid out for that one height; a
  // compact card clipped them and a readable one stretched the picture.
  @override
  Widget build(BuildContext context) => NexCardDensityScope(
    density: NexCardDensity.standard,
    child: Builder(builder: _card),
  );

  Widget _card(BuildContext context) {
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
    final picture = image;
    return Padding(
      padding: nexCardInsets,
      child: SizedBox(
        // Exactly a note card, not a floor it may grow past. The card belongs
        // to the stream, and a banner that is taller than everything around
        // it has stopped being one item in a list and started being an
        // interruption.
        height: nexCardHeightFor(context),
        child: Material(
          color: ground,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          child: InkWell(
            onTap: sponsor.url == null ? null : onOpen,
            borderRadius: BorderRadius.circular(NexRadius.lg),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(NexRadius.lg),
                border: Border.all(color: tint.withValues(alpha: 0.45)),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (picture == null)
                    _Words(sponsor: sponsor, tint: tint, onDismiss: onDismiss)
                  else
                    _Picture(
                      sponsor: sponsor,
                      picture: picture,
                      onDismiss: onDismiss,
                    ),
                  if (onDismiss case final dismiss?)
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: _Dismiss(
                        onDismiss: dismiss,
                        onImage: picture != null,
                      ),
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

/// Less above and below than a note card. The label, a title and a line of
/// body come to 52 at the default size, four more than a note card's 48, and
/// with the full inset they spilled out of the bottom of the card.
const _wordsInsets = EdgeInsets.symmetric(
  horizontal: NexSpacing.cardInset,
  vertical: NexSpacing.cardInset / 2,
);

/// The version with no picture: a glyph, the words, and the card's colour.
class _Words extends StatelessWidget {
  const _Words({
    required this.sponsor,
    required this.tint,
    required this.onDismiss,
  });

  final NexSponsor sponsor;
  final Color tint;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final body = sponsor.body;
    return Padding(
      padding: _wordsInsets,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context);
          double line(TextStyle? style) =>
              scale.scale(style?.fontSize ?? 12) * (style?.height ?? 1.5);
          final showBody =
              body != null &&
              body.isNotEmpty &&
              line(theme.textTheme.labelSmall) +
                      line(theme.textTheme.titleSmall) +
                      line(theme.textTheme.bodySmall) <=
                  constraints.maxHeight;
          return Row(
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
                    // Says what it is, in small type, above the words somebody
                    // paid for. Not a disclosure buried at the bottom — the
                    // label is the first thing read.
                    Text(
                      l10n.sponsorLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      sponsor.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: nexDirectionOf(sponsor.title),
                      style: theme.textTheme.titleSmall,
                    ),
                    if (showBody)
                      Text(
                        body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: nexDirectionOf(body),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (onDismiss != null) const SizedBox(width: nexMinTapTarget),
            ],
          );
        },
      ),
    );
  }
}

/// The version with a picture: the image fills the card, and the words sit on
/// a scrim over it.
///
/// Full bleed rather than a thumbnail beside text, because a card the height
/// of one note has room for one or the other, and a banner someone designed
/// is worth more than a 48dp square of it. The scrim is what keeps the label
/// legible over a picture nobody here has seen — it is only as dark as it
/// needs to be at the leading edge, and clear by the middle.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.sponsor,
    required this.picture,
    required this.onDismiss,
  });

  final NexSponsor sponsor;
  final File picture;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pixels =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .ceil();
    return Image.file(
      picture,
      fit: BoxFit.cover,
      cacheWidth: pixels > 0 ? pixels.clamp(1, 4096).toInt() : null,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => _Words(
        sponsor: sponsor,
        tint: nexParseTagColor(sponsor.color) ?? theme.colorScheme.primary,
        onDismiss: onDismiss,
      ),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null) {
          return _Words(
            sponsor: sponsor,
            tint: nexParseTagColor(sponsor.color) ?? theme.colorScheme.primary,
            onDismiss: onDismiss,
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
            Padding(
              padding: _wordsInsets,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final scale = MediaQuery.textScalerOf(context);
                        final heading = theme.textTheme.titleSmall;
                        final label = theme.textTheme.labelSmall;
                        double line(TextStyle? style) =>
                            scale.scale(style?.fontSize ?? 12) *
                            (style?.height ?? 1.5);
                        final lines =
                            ((constraints.maxHeight - line(label)) /
                                    line(heading))
                                .floor()
                                .clamp(1, 2);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.sponsorLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: label?.copyWith(
                                color: Colors.white70,
                                letterSpacing: 0.6,
                              ),
                            ),
                            Text(
                              sponsor.title,
                              maxLines: lines,
                              overflow: TextOverflow.ellipsis,
                              textDirection: nexDirectionOf(sponsor.title),
                              style: heading?.copyWith(color: Colors.white),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (onDismiss != null) const SizedBox(width: nexMinTapTarget),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A real tap target, not a 16dp cross.
///
/// Putting a card in somebody's list obliges the app to make it easy to take
/// back out.
class _Dismiss extends StatelessWidget {
  const _Dismiss({required this.onDismiss, this.onImage = false});

  final VoidCallback onDismiss;
  final bool onImage;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: AppLocalizations.of(context).sponsorDismiss,
    icon: const Icon(Icons.close, size: 16),
    style: onImage
        ? IconButton.styleFrom(backgroundColor: Colors.black54)
        : null,
    color: onImage ? Colors.white : null,
    constraints: const BoxConstraints.tightFor(
      width: nexMinTapTarget,
      height: nexMinTapTarget,
    ),
    onPressed: onDismiss,
  );
}
