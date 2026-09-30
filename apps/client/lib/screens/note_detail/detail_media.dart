part of '../note_detail_sheet.dart';

class _VoicePlayerControls extends StatelessWidget {
  const _VoicePlayerControls({
    this.path,
    required this.player,
    required this.position,
    required this.duration,
  });

  final String? path;
  final AudioPlayer player;
  final Duration position;
  final Duration duration;

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds;
    return Column(
      children: [
        if (path != null)
          AudioWaveform(
            path: path!,
            progress: position.inMilliseconds / totalMs,
          ),
        Row(
          children: [
            StreamBuilder<PlayerState>(
              stream: player.playerStateStream,
              builder: (context, snap) {
                final playing = snap.data?.playing ?? false;
                return IconButton.filled(
                  tooltip: playing
                      ? AppLocalizations.of(context).pauseAudio
                      : AppLocalizations.of(context).playAudio,
                  onPressed: () {
                    if (playing) {
                      player.pause();
                    } else {
                      player.play();
                    }
                  },
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                );
              },
            ),
            Expanded(
              child: Slider(
                semanticFormatterCallback: (value) =>
                    _fmt(Duration(milliseconds: value.round())),
                value: position.inMilliseconds.clamp(0, totalMs).toDouble(),
                max: totalMs.toDouble(),
                onChanged: (v) =>
                    player.seek(Duration(milliseconds: v.round())),
              ),
            ),
            Text(
              nexDigits(
                '${_fmt(position)} / ${_fmt(duration)}',
                persian: Localizations.localeOf(context).languageCode == 'fa',
              ),
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _FullScreenPhoto extends StatefulWidget {
  const _FullScreenPhoto({required this.path});

  final String path;

  @override
  State<_FullScreenPhoto> createState() => _FullScreenPhotoState();
}

class _FullScreenPhotoState extends State<_FullScreenPhoto>
    with SingleTickerProviderStateMixin {
  double _dragDy = 0;
  double _dragDx = 0;

  /// The zoom. Owned here so dismissal and double-tap can inspect the current
  /// transform without rebuilding the viewer on every pinch frame.
  final TransformationController _zoom = TransformationController();

  late final AnimationController _zoomDrive = AnimationController(
    vsync: this,
    duration: NexMotion.standard,
  );
  Animation<Matrix4>? _zoomTween;

  /// Past this much downward drag, releasing closes the viewer instead of
  /// springing back — the photo equivalent of the swipe card's own commit
  /// threshold.
  static const _dismissDistance = 120.0;

  /// Far enough in to read the small print on a photographed receipt, which
  /// is most of what anyone zooms a note's photo for.
  static const _maxScale = 8.0;

  /// Where a double tap lands, and comes back from.
  static const _tapScale = 3.0;

  /// Where the last double tap was, in the viewer's coordinates, so the zoom
  /// grows around what was tapped instead of around the corner of the image.
  Offset _tapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _zoomDrive.addListener(() {
      final tween = _zoomTween;
      if (tween != null) _zoom.value = tween.value;
    });
  }

  @override
  void dispose() {
    _zoomDrive.dispose();
    _zoom.dispose();
    super.dispose();
  }

  double get _scale => _zoom.value.getMaxScaleOnAxis();

  bool get _zoomedIn => _scale > 1.01;

  void _onInteractionStart(ScaleStartDetails _) {
    // A finger arriving during a double-tap animation takes ownership of the
    // transform. Otherwise the animation keeps overwriting the user's pan.
    _zoomDrive.stop();
    _zoomTween = null;
    _dragDx = 0;
    if (_dragDy != 0) setState(() => _dragDy = 0);
  }

  /// A one-finger drag means two different things depending on the zoom, and
  /// this is where they are told apart.
  ///
  /// At 1× the photo fits the screen and a drag down closes the viewer.
  /// Zoomed in, the same gesture pans the image instead.
  ///
  /// The dismissal is driven from the viewer's own callbacks rather than
  /// from a `GestureDetector` wrapped around it. A drag recognizer sitting
  /// over an [InteractiveViewer] competes with its scale recognizer in the
  /// gesture arena, and a pinch starts as two pointers moving in some
  /// direction, so which one won was a coin toss.
  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount != 1 || _zoomedIn) {
      _dragDx = 0;
      if (_dragDy != 0) setState(() => _dragDy = 0);
      return;
    }
    _dragDx += details.focalPointDelta.dx;
    setState(() {
      _dragDy = (_dragDy + details.focalPointDelta.dy).clamp(
        0.0,
        double.infinity,
      );
    });
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final downwardFling = velocity.dy > 800 && velocity.dy > velocity.dx.abs();
    final downwardDrag = _dragDy > _dismissDistance && _dragDy > _dragDx.abs();
    if (!_zoomedIn && (downwardDrag || (downwardFling && _dragDy > 0))) {
      Navigator.of(context).pop();
      return;
    }
    _dragDx = 0;
    if (_dragDy != 0) setState(() => _dragDy = 0);
  }

  /// Zoom without a pinch — the affordance most people reach for first, and
  /// the only one available one-handed.
  ///
  /// Around the point that was tapped, which is the half that was missing:
  /// a matrix that only scales grows the image around its own top-left
  /// corner, so double-tapping the middle of a photo threw the part you were
  /// looking at off the screen. The tap position is kept by
  /// [_onDoubleTapDown] because the double-tap callback itself is not given
  /// one.
  void _onDoubleTap() {
    _zoomDrive.stop();
    final target = _zoomedIn
        ? Matrix4.identity()
        // x -> s*x + (1 - s)*p leaves the tapped point where it was.
        : (Matrix4.diagonal3Values(_tapScale, _tapScale, 1)
            ..setEntry(0, 3, (1 - _tapScale) * _tapAt.dx)
            ..setEntry(1, 3, (1 - _tapScale) * _tapAt.dy));
    _zoomTween = Matrix4Tween(
      begin: _zoom.value,
      end: target,
    ).animate(CurvedAnimation(parent: _zoomDrive, curve: NexMotion.curve));
    _zoomDrive.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragDy / _dismissDistance).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Color.lerp(Colors.black, Colors.transparent, progress),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // Only a double tap out here, and it is safe where a drag was not: a
      // double-tap recognizer needs two taps in quick succession, so it never
      // competes with a pinch or a pan for the same pointers.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTapDown: (details) => _tapAt = details.localPosition,
        onDoubleTap: _onDoubleTap,
        // Outside the viewer, not inside it. A transform *inside* moves the
        // child out from under the matrix the viewer is maintaining, which is
        // the other half of why this felt like it was fighting back.
        child: Transform.translate(
          offset: Offset(0, _dragDy),
          child: InteractiveViewer(
            transformationController: _zoom,
            // Keep panning within the scaled image. An infinite margin lets
            // the photo drift completely off-screen and become hard to find.
            boundaryMargin: EdgeInsets.zero,
            minScale: 1,
            maxScale: _maxScale,
            // Leave the recognizer active throughout a pinch. Switching this
            // mid-gesture makes the next one-finger pan intermittent.
            panEnabled: true,
            onInteractionStart: _onInteractionStart,
            onInteractionUpdate: _onInteractionUpdate,
            onInteractionEnd: _onInteractionEnd,
            child: Center(
              child: Image.file(File(widget.path), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

/// An image that arrived as a file rather than through the camera.
///
/// The same picture in the same app looked entirely different depending on
/// which door it came in by: one captured or picked was shown full width and
/// opened into the viewer, and one dropped on the share sheet was a filename
/// and a byte count. Same picture, same gesture, same viewer, either way now.
// Decode to the display width only. Giving both cache dimensions forces an
// exact resize and changes a portrait photo's aspect ratio before BoxFit runs.
// Some widget hosts report zero width while measuring; let Image.file choose
// its own decode size in that case.
int? _imageCacheWidth(BuildContext context) {
  final pixels =
      MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context);
  return pixels >= 1 ? pixels.round() : null;
}

class _ImageFileBody extends StatelessWidget {
  const _ImageFileBody({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (!File(path).existsSync()) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              NexPageRoute<void>(
                builder: (_) => _FullScreenPhoto(path: path),
                swipeBackEnabled: false,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NexRadius.md),
              child: Image.file(
                File(path),
                semanticLabel: l10n.photo,
                fit: BoxFit.contain,
                height: 220,
                width: double.infinity,
                cacheWidth: _imageCacheWidth(context),
                // A file named `.png` that is not one lands here as a decode
                // failure rather than as a crash. Nothing is drawn, and the
                // row above still says everything the file itself knows.
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(l10n.tapToExpand, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// The first page of a PDF, drawn by the platform.
///
/// A picture of the page rather than a reader. Opening a PDF properly means a
/// viewer with search, selection, links and a page count, and the device
/// already has one that does all of that — so this answers the question a note
/// actually raises ("which file is this?") and hands the rest to whatever
/// opens PDFs, on the same tap.
///
/// Nothing is drawn where there is no renderer: on a platform without the
/// native half, on a file that is not really a PDF, on an encrypted one. The
/// row above still names the file and still opens it, which is what it did
/// before this existed.
class _PdfBody extends StatefulWidget {
  const _PdfBody({required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  /// How much of the first page to show.
  ///
  /// A page is much taller than it is wide, and a full one at the width of a
  /// sheet would be most of the screen for a thumbnail. This is the top of the
  /// page — the part with the title on it — which is how a file manager shows
  /// one too.
  static const height = 320.0;

  @override
  State<_PdfBody> createState() => _PdfBodyState();
}

class _PdfBodyState extends State<_PdfBody> {
  Uint8List? _page;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Assigned rather than set: `setState` here would fire during a build.
    _loading = true;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_PdfBody old) {
    super.didUpdateWidget(old);
    if (old.path == widget.path) return;
    _page = null;
    _loading = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final path = widget.path;
    final page = await NexPdfPreview.firstPage(path);
    // The sheet is reused across notes, so an answer that arrives after it has
    // moved on belongs to a file nobody is looking at.
    if (!mounted || widget.path != path) return;
    setState(() {
      _page = page;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: NexSpacing.sm),
        child: NexSkeleton(height: 16),
      );
    }
    final page = _page;
    if (page == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NexRadius.md),
            // A rendered page is paper — white, whatever the app's theme is —
            // so it needs an edge of its own to sit on a dark background
            // without looking like a hole in it.
            border: Border.all(color: scheme.outlineVariant),
          ),
          // A cap rather than a fixed height: a landscape page is shorter than
          // the band and should not be given a strip of empty sheet under it.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _PdfBody.height),
            child: Image.memory(
              page,
              fit: BoxFit.fitWidth,
              // The top of the page, not the middle of it.
              alignment: Alignment.topCenter,
              width: double.infinity,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

/// A frame of a video, drawn by the platform, standing in for the video.
///
/// The same answer as the PDF above, arrived at the same way. Playing a video
/// in a note means a player, a render surface and a codec plugin; the question
/// a note actually raises about a video file is "which one is this?", and one
/// frame answers it. The tap hands the file to whatever plays video on this
/// device, which is where scrubbing and volume belong.
///
/// Nothing is drawn where there is no frame to be had: on a platform without
/// the native half, on a file that is not really a video, on one in a codec
/// this device cannot decode. The row above still names the file and still
/// opens it, which is what it did before this existed.
class _VideoBody extends StatefulWidget {
  const _VideoBody({required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  /// The same height a shared image gets. A video and a photo in a note are
  /// the same kind of thing to look at, and giving them different heights
  /// would make a timeline of both look like two apps.
  static const height = 220.0;

  @override
  State<_VideoBody> createState() => _VideoBodyState();
}

class _VideoBodyState extends State<_VideoBody> {
  Uint8List? _poster;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Assigned rather than set: `setState` here would fire during a build.
    _loading = true;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_VideoBody old) {
    super.didUpdateWidget(old);
    if (old.path == widget.path) return;
    _poster = null;
    _loading = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final path = widget.path;
    final poster = await NexVideoPreview.poster(path);
    // The sheet is reused across notes, so an answer that arrives after it has
    // moved on belongs to a file nobody is looking at.
    if (!mounted || widget.path != path) return;
    setState(() {
      _poster = poster;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: NexSpacing.sm),
        child: NexSkeleton(height: 16),
      );
    }
    final poster = _poster;
    if (poster == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NexRadius.md),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.memory(
                poster,
                fit: BoxFit.cover,
                height: _VideoBody.height,
                width: double.infinity,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              // What tells a still picture from a video. Its own dark disc
              // rather than a bare icon, because the frame underneath it is
              // somebody else's photograph and a white glyph on a white wall
              // is nothing at all.
              const _PlayBadge(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The play glyph over a video's cover.
///
/// Fixed colours, not the theme's: it sits on a frame of video, which is as
/// likely to be bright under a dark theme as it is to be dark under a light
/// one. What it needs to be legible against is the picture, not the app.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        color: Color(0x8C000000),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Color(0xFFFFFFFF),
        size: 34,
      ),
    );
  }
}
