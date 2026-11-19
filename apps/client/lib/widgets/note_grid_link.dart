part of 'note_grid_card.dart';

/// A video with no picture yet — saved offline, or from a site out of
/// reach: a small screen in the site's colour with Play on it, so it reads
/// as a video at a glance (2.8.3).
class _VideoScreen extends StatelessWidget {
  const _VideoScreen({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('grid-link-screen'),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(NexRadius.md),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(color, Colors.black, 0.25)!,
          Color.lerp(color, Colors.black, 0.7)!,
        ],
      ),
    ),
    child: Center(
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.play_arrow_rounded, color: color, size: 26),
      ),
    ),
  );
}

/// A link's tile without a picture of its page: the site's mark and name,
/// what the address points at, a small screen for a video, and what the
/// page is called (2.8.2, 2.8.3).
class _SiteCard extends StatelessWidget {
  const _SiteCard({
    required this.note,
    required this.title,
    required this.tint,
    required this.muted,
    required this.titleStyle,
    required this.bodyStyle,
    required this.fitting,
    required this.height,
  });

  final Note note;
  final String title;
  final Color tint;
  final Color muted;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;
  final (int, double) Function(String, TextStyle?, double) fitting;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final face = NexLinkFace.of(note.linkUrl ?? '');
    final icon = NexLinkArt.instance.of(note.id)?.icon;
    final words = nexLinkHeadline(note, title, face);
    final kind = face.kind == NexLinkKind.page
        ? null
        : AppLocalizations.of(context).tileLinkKind(face.kind.name);
    final brand = face.brandColor != null;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    final siteHeight = math.max(
      _gridSiteMark,
      fitting('Ag آگ', bodyStyle, 1000).$2 +
          (kind == null ? 0 : fitting('Ag آگ', labelStyle, 1000).$2),
    );
    var room = height - siteHeight - NexSpacing.sm;
    // A small screen for a video, when it leaves a line for the title.
    final lineHeight = fitting('M', titleStyle, 1000).$2;
    final screen = face.kind == NexLinkKind.video
        ? math.min(
            room - (words.isEmpty ? 0 : lineHeight + NexSpacing.sm),
            96.0,
          )
        : 0.0;
    final showScreen = screen >= 48;
    if (showScreen) room -= screen + NexSpacing.sm;
    final lines = words.isEmpty ? 0 : fitting(words, titleStyle, room).$1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            NexSiteMark(
              face: face,
              icon: icon,
              size: _gridSiteMark,
              tint: tint,
            ),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    face.host.isEmpty ? (note.linkUrl ?? '') : face.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // A host is an address, read left to right; a name is a
                    // word, and lines up with the rest.
                    textDirection: brand ? null : TextDirection.ltr,
                    textAlign: brand
                        ? TextAlign.start
                        : Directionality.of(context) == TextDirection.rtl
                        ? TextAlign.right
                        : TextAlign.left,
                    style: bodyStyle?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (kind != null)
                    Text(
                      kind,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle?.copyWith(color: muted),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (showScreen) ...[
          const SizedBox(height: NexSpacing.sm),
          SizedBox(
            height: screen,
            child: _VideoScreen(color: nexSiteColor(face, scheme)),
          ),
        ],
        if (lines > 0) ...[
          const SizedBox(height: NexSpacing.sm),
          Text(
            words,
            key: const ValueKey('grid-link-title'),
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            textDirection: nexDirectionOf(words),
            style: titleStyle,
          ),
        ],
      ],
    );
  }
}

/// A link whose site gave a picture: the picture fills the tile, the site's
/// mark and name over it, and Play on a video (2.8.3).
extension on _MediaTileState {
  Widget _linkTile() {
    final note = widget.note;
    final art = NexLinkArt.instance.of(note.id);
    final cover = art?.cover;
    if (cover == null) return widget.fallback(context);
    final face = NexLinkFace.of(note.linkUrl ?? '');
    final words = nexLinkHeadline(note, note.title ?? '', face);
    final kind = face.kind == NexLinkKind.page
        ? null
        : AppLocalizations.of(context).tileLinkKind(face.kind.name);
    final picture = NexParallaxImage(
      image: ResizeImage.resizeIfNeeded(
        (widget.metrics.tileWidth *
                1.6 *
                MediaQuery.devicePixelRatioOf(context))
            .round(),
        null,
        FileImage(cover),
      ),
      errorBuilder: (context, error, stack) =>
          ColoredBox(color: widget.tint.withValues(alpha: 0.14)),
    );
    final chip = Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.xs),
      child: Row(
        key: const ValueKey('grid-link-site'),
        children: [
          NexSiteMark(face: face, icon: art?.icon, size: 20, tint: widget.tint),
          const SizedBox(width: NexSpacing.xs + 2),
          Flexible(
            child: Text(
              [face.name, ?kind].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                shadows: const [
                  Shadow(color: Color(0x66000000), blurRadius: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return _tile(
      picture,
      center: face.kind == NexLinkKind.video ? const _PlayBadge() : null,
      chip: chip,
      text: words,
    );
  }
}
