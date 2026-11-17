part of 'note_grid_card.dart';

/// What a link's tile calls it: the page's own title, or the one its address
/// spells out — never the address again, which the site's name already says.
String _linkWords(Note note, String title, NexLinkFace face) {
  final url = (note.linkUrl ?? '').trim();
  final bare = title.trim().toLowerCase().replaceFirst(
    RegExp(r'^(https?://)?(www\.)?'),
    '',
  );
  final host = face.host.toLowerCase();
  final onlyAddress =
      title.trim().isEmpty ||
      title.trim() == url ||
      bare == host ||
      bare.startsWith('$host/') && !title.contains(' ');
  return onlyAddress ? (face.title ?? '') : title;
}

/// The colour a site is drawn in: its own when it is one people know, one
/// worked out from its address otherwise — the same site, the same colour.
Color _siteColor(NexLinkFace face, ColorScheme scheme) {
  if (face.brandColor case final brand?) return Color(brand);
  final hue =
      face.host.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0xffff) % 360;
  return HSLColor.fromAHSL(
    1,
    hue.toDouble(),
    0.55,
    scheme.brightness == Brightness.dark ? 0.62 : 0.46,
  ).toColor();
}

/// The site's mark: its own icon when it gave one, otherwise its initial on
/// its colour (2.8.3).
class _SiteMark extends StatelessWidget {
  const _SiteMark({
    required this.face,
    required this.icon,
    required this.size,
    required this.tint,
  });

  final NexLinkFace face;
  final File? icon;
  final double size;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _siteColor(face, scheme);
    final radius = BorderRadius.circular(size * 0.3);
    if (icon case final file?) {
      return Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Image.file(
          file,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (context, error, stack) => const SizedBox.shrink(),
        ),
      );
    }
    final letter = face.name.isEmpty
        ? '#'
        : face.name.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, tint, 0.4)!],
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: nexReadableOn(Colors.white, color),
          fontWeight: FontWeight.w800,
          fontSize: size * 0.48,
          height: 1,
        ),
      ),
    );
  }
}

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
    const markSize = 34.0;
    final words = _linkWords(note, title, face);
    final kind = face.kind == NexLinkKind.page
        ? null
        : AppLocalizations.of(context).tileLinkKind(face.kind.name);
    final brand = face.brandColor != null;
    var room = height - markSize - NexSpacing.sm;
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
            _SiteMark(face: face, icon: icon, size: markSize, tint: tint),
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
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: muted),
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
            child: _VideoScreen(color: _siteColor(face, scheme)),
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
    final words = _linkWords(note, note.title ?? '', face);
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
          _SiteMark(face: face, icon: art?.icon, size: 20, tint: widget.tint),
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
