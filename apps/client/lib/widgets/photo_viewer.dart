import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;
import 'package:nex_ui/nex_ui.dart';

/// A photo full screen: pinch or double-tap to zoom around where you
/// touched, drag down at 1× to close. The one viewer for a note's photo and
/// a private message's alike, so a photo behaves the same wherever it is.
class NexPhotoViewer extends StatelessWidget {
  const NexPhotoViewer({super.key, required this.image});

  /// A photo on disk — a note's.
  NexPhotoViewer.file(String path, {super.key}) : image = FileImage(File(path));

  /// A photo held only in memory — one decrypted from the private vault,
  /// which never touches the disk in the clear.
  NexPhotoViewer.memory(Uint8List bytes, {super.key})
    : image = MemoryImage(bytes);

  final ImageProvider image;

  @override
  Widget build(BuildContext context) => _PhotoViewer(image: image);
}

/// One photo in a [NexPhotoGallery]: where it is, and what was written
/// under it.
class NexGalleryPhoto {
  const NexGalleryPhoto(this.path, {this.caption});

  final String path;
  final String? caption;
}

/// Every photo a note holds, full screen, one swipe apart: its own and each
/// one attached to it. A count at the top says where you are, and a photo's
/// caption sits at the bottom. Each page is the same viewer as a single
/// photo — pinch, double-tap, drag down to close — and while one is zoomed
/// in, a sideways drag pans it instead of turning the page.
class NexPhotoGallery extends StatefulWidget {
  const NexPhotoGallery({super.key, required this.photos, this.initial = 0});

  final List<NexGalleryPhoto> photos;
  final int initial;

  @override
  State<NexPhotoGallery> createState() => _NexPhotoGalleryState();
}

class _NexPhotoGalleryState extends State<NexPhotoGallery> {
  late final PageController _pages = PageController(
    initialPage: widget.initial.clamp(0, widget.photos.length - 1),
  );
  late int _at = widget.initial.clamp(0, widget.photos.length - 1);
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final photo = widget.photos[_at];
    final caption = photo.caption?.trim() ?? '';
    final many = widget.photos.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: many
            ? Text(
                nexDigits(
                  '${_at + 1} / ${widget.photos.length}',
                  persian: persian,
                ),
                key: const ValueKey('gallery-position'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.photos.length,
            onPageChanged: (index) => setState(() {
              _at = index;
              _zoomed = false;
            }),
            itemBuilder: (context, index) => _PhotoViewer(
              key: ValueKey(widget.photos[index].path),
              image: FileImage(File(widget.photos[index].path)),
              framed: false,
              onZoomed: (zoomed) {
                if (index == _at && zoomed != _zoomed) {
                  setState(() => _zoomed = zoomed);
                }
              },
            ),
          ),
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: NexMotion.of(context, NexMotion.standard),
                child: caption.isEmpty || _zoomed
                    ? const SizedBox.shrink()
                    : DecoratedBox(
                        key: ValueKey(_at),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xCC000000), Color(0x00000000)],
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              NexSpacing.lg,
                              NexSpacing.xl,
                              NexSpacing.lg,
                              NexSpacing.lg,
                            ),
                            child: Text(
                              caption,
                              textDirection: nexDirectionOf(caption),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    super.key,
    required this.image,
    this.framed = true,
    this.onZoomed,
  });

  final ImageProvider image;

  /// Its own black page with a close button, or a page inside a gallery
  /// that provides those.
  final bool framed;

  /// Told when the photo is zoomed in or back to fit, so a gallery can stop
  /// turning pages under a pan.
  final ValueChanged<bool>? onZoomed;

  @override
  State<_PhotoViewer> createState() => _FullScreenPhotoState();
}

class _FullScreenPhotoState extends State<_PhotoViewer>
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

  bool _wasZoomed = false;

  @override
  void initState() {
    super.initState();
    _zoomDrive.addListener(() {
      final tween = _zoomTween;
      if (tween != null) _zoom.value = tween.value;
    });
    _zoom.addListener(() {
      final zoomed = _zoomedIn;
      if (zoomed == _wasZoomed) return;
      _wasZoomed = zoomed;
      widget.onZoomed?.call(zoomed);
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
    // Only a double tap out here, and it is safe where a drag was not: a
    // double-tap recognizer needs two taps in quick succession, so it never
    // competes with a pinch or a pan for the same pointers.
    final body = GestureDetector(
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
            child: Image(image: widget.image, fit: BoxFit.contain),
          ),
        ),
      ),
    );
    if (!widget.framed) {
      return Opacity(opacity: 1 - progress * 0.6, child: body);
    }
    return Scaffold(
      backgroundColor: Color.lerp(Colors.black, Colors.transparent, progress),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: body,
    );
  }
}
