part of 'note_grid_card.dart';

/// Where a photo note's other pictures come from, for its collage: their
/// files, in order. Null where the grid cannot read attachments.
typedef NexTilePhotos = Future<List<String>> Function(Note note);

/// A tile whose note is a picture — a photo, a few of them, a video's frame,
/// a PDF's first page — wearing it from edge to edge (2.8.2).
///
/// The words a tile usually shows give way to the picture: the kind's mark
/// stays at the top and the reminder, tags and time at the foot, both on a
/// soft dark fall-off so they read over any image, with the note's caption
/// or name above the foot. A single picture drifts against the scroll (see
/// [NexParallaxImage]); a collage and a PDF's page hold still.
///
/// The ink splash of a tap is drawn under a widget's children, so on a tile
/// that is all picture it was never seen: a press dims the picture instead.
class _MediaTile extends StatefulWidget {
  const _MediaTile({
    super.key,
    required this.note,
    required this.backdrop,
    required this.kind,
    required this.tint,
    required this.edge,
    required this.metrics,
    required this.strings,
    required this.selected,
    required this.ringing,
    required this.onTap,
    required this.onLeadingTap,
    required this.photos,
    required this.fallback,
  });

  final Note note;
  final NexTileBackdrop backdrop;
  final String kind;
  final Color tint;
  final BorderSide edge;
  final NexGridMetrics metrics;
  final NexCardStrings strings;
  final bool? selected;
  final bool ringing;
  final VoidCallback onTap;
  final VoidCallback? onLeadingTap;
  final NexTilePhotos? photos;

  /// The tile as words, for a file whose picture could not be had.
  final WidgetBuilder fallback;

  @override
  State<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<_MediaTile> {
  final _pressed = ValueNotifier(false);

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  String get _path => widget.note.mediaUri ?? '';

  @override
  Widget build(BuildContext context) => switch (widget.backdrop) {
    NexTileBackdrop.video => _waitFor<Uint8List?>(
      known: NexTilePreviews.knownFrame(_path)?.bytes,
      isKnown: NexTilePreviews.knownFrame(_path) != null,
      future: () => NexTilePreviews.frame(_path),
      build: (bytes) => _tile(
        // A frame preview is 720 device pixels wide; the tile needs no
        // more than the same 1.6x-tile budget the file photos use, so the
        // rest is never decoded into memory.
        NexParallaxImage(
          image: ResizeImage.resizeIfNeeded(
            (widget.metrics.tileWidth *
                    1.6 *
                    MediaQuery.devicePixelRatioOf(context))
                .round(),
            null,
            MemoryImage(bytes!),
          ),
        ),
        center: const _PlayBadge(),
      ),
    ),
    NexTileBackdrop.pdf => _waitFor<NexTilePage?>(
      known: NexTilePreviews.knownPage(_path)?.page,
      isKnown: NexTilePreviews.knownPage(_path) != null,
      future: () => NexTilePreviews.page(_path),
      build: (page) => _tile(
        _PdfPage(
          bytes: page!.bytes,
          cacheWidth:
              (widget.metrics.tileWidth *
                      1.6 *
                      MediaQuery.devicePixelRatioOf(context))
                  .round(),
        ),
        badge: AppLocalizations.of(context).tilePdfPages(page.pages),
        lightPicture: true,
      ),
    ),
    NexTileBackdrop.collage when widget.photos != null => _collage(),
    NexTileBackdrop.link => _linkTile(),
    _ => _tile(_photo(_path)),
  };

  /// A picture that has to be asked for: the tile in its colour while it is
  /// read, the picture once it is there, the tile as words if there is none.
  Widget _waitFor<T>({
    required T known,
    required bool isKnown,
    required Future<T> Function() future,
    required Widget Function(T value) build,
  }) {
    if (isKnown) {
      return known == null ? widget.fallback(context) : build(known);
    }
    return FutureBuilder<T>(
      future: future(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _tile(_Waiting(tint: widget.tint));
        }
        final value = snapshot.data;
        return value == null ? widget.fallback(context) : build(value);
      },
    );
  }

  Widget _photo(String path, {bool drift = true}) {
    final image = ResizeImage.resizeIfNeeded(
      (widget.metrics.tileWidth * 1.6 * MediaQuery.devicePixelRatioOf(context))
          .round(),
      null,
      FileImage(File(path)),
    );
    Widget broken(BuildContext context, Object error, StackTrace? stack) =>
        ColoredBox(
          color: widget.tint.withValues(alpha: 0.14),
          child: Icon(
            Icons.image_not_supported_outlined,
            color: widget.tint.withValues(alpha: 0.6),
          ),
        );
    return drift
        ? NexParallaxImage(image: image, errorBuilder: broken)
        : Image(
            image: image,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: broken,
          );
  }

  Widget _collage() {
    final key =
        '${widget.note.id}:${widget.note.attachmentCount}:'
        '${widget.note.updatedAt.microsecondsSinceEpoch}';
    final known = _collages[key];
    Widget built(List<String> more) {
      final all = [_path, ...more];
      if (all.length < 2) return _tile(_photo(_path));
      const gap = SizedBox.square(dimension: 2);
      final extra = all.length - 3;
      Widget cell(int i) => Stack(
        fit: StackFit.expand,
        children: [
          _photo(all[i], drift: false),
          if (i == 2 && extra > 0)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(
                child: Text(
                  AppLocalizations.of(context).tileMorePhotos(extra),
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      );
      return _tile(
        ColoredBox(
          color: Colors.black,
          child: all.length == 2
              ? Row(
                  children: [
                    Expanded(child: cell(0)),
                    gap,
                    Expanded(child: cell(1)),
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 3, child: cell(0)),
                    gap,
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Expanded(child: cell(1)),
                          gap,
                          Expanded(child: cell(2)),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    if (known != null) return built(known);
    return FutureBuilder<List<String>>(
      future: widget.photos!(widget.note).then((paths) {
        if (_collages.length > 200) _collages.clear();
        return _collages[key] = paths;
      }, onError: (Object _) => const <String>[]),
      builder: (context, snapshot) => built(snapshot.data ?? const []),
    );
  }

  /// The picture, its fall-off, the mark, the caption and the foot.
  Widget _tile(
    Widget picture, {
    Widget? center,
    String? badge,
    Widget? chip,
    String? text,
    bool lightPicture = false,
  }) {
    final theme = Theme.of(context);
    final note = widget.note;
    final metrics = widget.metrics;
    const ink = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.82);
    final caption =
        text ??
        [
          note.title,
          note.caption,
          note.displayText,
          note.originalFilename,
        ].firstWhere(
          (t) => t != null && t.trim().isNotEmpty,
          orElse: () => null,
        );
    final words = caption == null
        ? ''
        : NexMarkdownText.preview(caption).replaceAll(RegExp(r'\s+'), ' ');
    const radius = BorderRadius.all(Radius.circular(NexRadius.xl));
    return ClipRRect(
      borderRadius: radius,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (down) => _pressed.value = down,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: widget.tint.withValues(alpha: 0.18)),
              picture,
              // A fall-off at the top for the mark and a deeper one at the
              // foot for the words: legible on a white page or a bright sky.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.28, 0.42, 0.78, 1],
                    colors: [
                      Colors.black.withValues(alpha: lightPicture ? 0.3 : 0.4),
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: lightPicture ? 0.72 : 0.6),
                      Colors.black.withValues(alpha: lightPicture ? 0.9 : 0.82),
                    ],
                  ),
                ),
              ),
              ?center,
              Padding(
                padding: EdgeInsets.all(metrics.padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Top(
                      note: note,
                      // The picture says what the note is; the mark keeps it.
                      kind: null,
                      tint: widget.tint,
                      ink: ink,
                      muted: muted,
                      disc: metrics.disc,
                      selected: widget.selected,
                      ringing: widget.ringing,
                      label: widget.strings.selectLabel,
                      onPick: widget.onLeadingTap,
                    ),
                    const Spacer(),
                    ?chip,
                    if (badge != null)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: NexSpacing.xs),
                          padding: const EdgeInsets.symmetric(
                            horizontal: NexSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(NexRadius.pill),
                          ),
                          child: Text(
                            badge,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (words.isNotEmpty)
                      Text(
                        words,
                        key: const ValueKey('grid-media-caption'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textDirection: nexDirectionOf(words),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          shadows: const [
                            Shadow(color: Color(0x66000000), blurRadius: 6),
                          ],
                        ),
                      ),
                    const SizedBox(height: NexSpacing.xs),
                    _Foot(
                      note: note,
                      strings: widget.strings,
                      roomForBoth: metrics.showKind,
                      ground: const Color(0xFF2A2A2A),
                      muted: muted,
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _pressed,
                builder: (context, down, _) => IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: down ? 1 : 0,
                    duration: NexMotion.of(context, NexMotion.fast),
                    child: const ColoredBox(color: Color(0x24000000)),
                  ),
                ),
              ),
              // The edge, over the picture: picked, high contrast, or the
              // kind's hairline.
              IgnorePointer(
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: ShapeDecoration(
                    shape: RoundedRectangleBorder(
                      borderRadius: radius,
                      side: widget.edge,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A photo note's other pictures, already read, by note and its state.
final _collages = <String, List<String>>{};

/// The tile in its colour while its picture is read.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.tint});

  final Color tint;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tint.withValues(alpha: 0.28), tint.withValues(alpha: 0.12)],
      ),
    ),
  );
}

/// A PDF's first page: white paper from the top, as a document is read.
class _PdfPage extends StatelessWidget {
  const _PdfPage({required this.bytes, required this.cacheWidth});

  final Uint8List bytes;

  /// The decode width the tile is willing to pay for — see the caller.
  final int cacheWidth;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: Image.memory(
      bytes,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      gaplessPlayback: true,
      // The page bitmap is bounded to three million pixels, a page-shape
      // thumbnail; the tile it is drawn into is far smaller, and the same
      // resize-if-needed policy keeps the decode proportional.
      cacheWidth: cacheWidth,
    ),
  );
}

/// A video's frame says it plays.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.42),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 28,
      ),
    ),
  );
}
