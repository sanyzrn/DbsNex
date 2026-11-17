part of '../timeline_screen.dart';

/// The notes as they were, laid over the new view while it fades in (2.8.2).
///
/// A filter chip, list or grid, "See all": the list becomes a view of
/// something else. The new one already faded in (2.7.1), but the old one
/// went on the frame of the tap, so what the eye met was a blink — the notes
/// gone, then coming back. Now the last frame of the old view is held as a
/// picture over the new one and fades out as it fades in: one view turning
/// into the other.
///
/// A picture, not the old cards kept alive: it costs one raster of what was
/// already on screen, never builds a card, and lets go of its pixels when
/// the fade ends. Only the notes take part — the picture is clipped to below
/// the filter row, so the greeting, the brief and the chips above (whose
/// selection animates by itself) are never drawn twice.
class _ViewDissolve extends ChangeNotifier {
  /// Around the list, so its last frame can be read back.
  final GlobalKey boundary = GlobalKey(debugLabel: 'timeline-view');

  ui.Image? _image;
  double _top = 0;

  ui.Image? get image => _image;

  /// Where the notes begin in the picture: under the filter row.
  double get top => _top;

  /// Keeps what is on screen now, before the rebuild that changes it.
  void capture(BuildContext context, GlobalKey line) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final box = boundary.currentContext?.findRenderObject();
    if (box is! _RenderLastFrame || !box.attached || !box.hasSize) return;
    var top = 0.0;
    final row = line.currentContext?.findRenderObject();
    if (row is RenderBox && row.attached && row.hasSize) {
      top = row
          .localToGlobal(Offset(0, row.size.height), ancestor: box)
          .dy
          .clamp(0.0, box.size.height);
    }
    final ui.Image? shot;
    try {
      shot = box.lastFrame(MediaQuery.devicePixelRatioOf(context));
    } catch (_) {
      return;
    }
    if (shot == null) return;
    _image?.dispose();
    _image = shot;
    _top = top;
    notifyListeners();
  }

  void clear() {
    final image = _image;
    if (image == null) return;
    _image = null;
    image.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}

/// [child] with the old view's picture over it while [fade] runs.
class _ViewDissolveLayer extends StatelessWidget {
  const _ViewDissolveLayer({
    required this.dissolve,
    required this.fade,
    required this.child,
  });

  final _ViewDissolve dissolve;
  final Animation<double> fade;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      _LastFrame(key: dissolve.boundary, child: child),
      Positioned.fill(
        child: IgnorePointer(
          child: ListenableBuilder(
            listenable: dissolve,
            builder: (context, _) => switch (dissolve.image) {
              final image? => CustomPaint(
                key: const ValueKey('timeline-view-dissolve'),
                painter: _DissolvePainter(image, dissolve.top, fade),
              ),
              null => const SizedBox.shrink(),
            },
          ),
        ),
      ),
    ],
  );
}

class _DissolvePainter extends CustomPainter {
  _DissolvePainter(this.image, this.top, this.fade) : super(repaint: fade);

  final ui.Image image;
  final double top;
  final Animation<double> fade;

  /// The old view is mostly gone by the time the new one is mostly there,
  /// so the two are never both half-seen for long.
  static const _leave = Interval(0, 0.65, curve: Curves.easeOut);

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = 1 - _leave.transform(fade.value.clamp(0.0, 1.0));
    if (opacity <= 0 || top >= size.height) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, top, size.width, size.height));
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, opacity)
        ..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DissolvePainter old) =>
      old.image != image || old.top != top || old.fade != fade;
}

/// A repaint boundary that can hand back the frame it last painted.
class _LastFrame extends SingleChildRenderObjectWidget {
  const _LastFrame({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLastFrame();
}

class _RenderLastFrame extends RenderRepaintBoundary {
  /// The layer still holds the last frame painted — the old view — even
  /// when a chip's ripple has already asked for the next one, which
  /// [toImageSync] would refuse.
  ui.Image? lastFrame(double pixelRatio) {
    final last = layer;
    if (last is! OffsetLayer) return null;
    return last.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
  }
}
