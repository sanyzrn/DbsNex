import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'nex_brand.dart';

/// The opening screen: one mind, a thousand connections.
///
/// It starts on the two eyes Android's own splash shows (the same size, in
/// the same place, see `tools/generate_brand_assets.py`), so the hand-over is
/// not seen. The blue eye blinks; the body spreads out from the eyes; scattered
/// pieces of a life — a thought, a photo, a person, a task, a moment, a voice —
/// are each caught by an arm, and a ripple marks where they join. Then the
/// octopus makes room for the wordmark and the line it stands for.
///
/// With animations turned off it shows the finished picture at once.
class NexSplash extends StatefulWidget {
  const NexSplash({super.key});

  /// How long the whole sequence runs. The bootstrap keeps the splash up at
  /// least this long, so a warm start still sees it to the end.
  static const duration = Duration(milliseconds: 1800);

  /// The mark's width on screen, matching the Android splash icon.
  static const markWidth = 96.0;

  @override
  State<NexSplash> createState() => _NexSplashState();
}

class _NexSplashState extends State<NexSplash> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: NexSplash.duration,
  );

  /// A slow pulse from the eyes once the picture is complete, so a long cold
  /// start does not look like a frozen one.
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
    } else {
      _intro.forward().whenComplete(() {
        if (mounted) _idle.repeat();
      });
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = NexBrand.ink(theme.brightness);
    final layout = _Layout();
    return SizedBox(
      width: _Layout.width,
      height: _Layout.height,
      child: AnimatedBuilder(
        animation: Listenable.merge([_intro, _idle]),
        builder: (context, _) {
          final t = _intro.value;
          final tagline = _interval(t, .86, 1, Curves.easeOutCubic);
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SplashPainter(
                    t: t,
                    idle: _idle.isAnimating ? _idle.value : null,
                    ink: ink,
                    fragments: _fragmentGlyphs(ink),
                    layout: layout,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: _Layout.height / 2 + layout.taglineTop,
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: tagline,
                    child: Transform.translate(
                      offset: Offset(0, (1 - tagline) * 6),
                      child: Text(
                        AppLocalizations.of(context).splashTagline,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: .2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<TextPainter>? _glyphs;
  Color? _glyphInk;

  List<TextPainter> _fragmentGlyphs(Color ink) {
    if (_glyphs != null && _glyphInk == ink) return _glyphs!;
    _glyphInk = ink;
    return _glyphs = [
      for (final fragment in _fragments)
        TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: String.fromCharCode(fragment.icon.codePoint),
            style: TextStyle(
              fontFamily: fragment.icon.fontFamily,
              package: fragment.icon.fontPackage,
              fontSize: 17,
              color: ink,
            ),
          ),
        )..layout(),
    ];
  }
}

/// A scattered piece of a life, and the point on the octopus that catches it.
class _Fragment {
  const _Fragment(this.icon, this.anchor, this.start);

  final IconData icon;

  /// On the mark's ink, in the mark's own coordinates.
  final Offset anchor;

  /// When it appears, as a fraction of the sequence.
  final double start;
}

const _fragments = [
  _Fragment(Icons.lightbulb_outline, Offset(118, 24), .16),
  _Fragment(Icons.photo_outlined, Offset(49, 95), .19),
  _Fragment(Icons.person_outline, Offset(187, 95), .22),
  _Fragment(Icons.check_circle_outline, Offset(24, 222), .25),
  _Fragment(Icons.schedule, Offset(212, 222), .28),
  _Fragment(Icons.mic_none, Offset(70, 248), .31),
];

/// How long one fragment's journey takes, as a fraction of the sequence.
const _fragmentSpan = .30;

/// Where things sit, in logical pixels from the centre of the splash.
class _Layout {
  _Layout() {
    final mark = NexBrand.markBounds;
    markScale = NexSplash.markWidth / mark.width;
    wordScale = _wordWidth / NexBrand.wordBounds.width;
    final markHeight = mark.height * markScale;
    final wordHeight = NexBrand.wordBounds.height * wordScale;
    final total = markHeight + _gap + wordHeight + _gap * .7 + _tagline;
    finalMarkY = -total / 2 + markHeight / 2;
    wordCentreY = -total / 2 + markHeight + _gap + wordHeight / 2;
    taglineTop = wordCentreY + wordHeight / 2 + _gap * .7;
  }

  static const width = 300.0;
  static const height = 340.0;
  static const _wordWidth = 116.0;
  static const _gap = 22.0;
  static const _tagline = 20.0;

  late final double markScale;
  late final double wordScale;

  /// The mark's centre once it has made room; it starts at 0, where the
  /// Android splash put its eyes.
  late final double finalMarkY;
  late final double wordCentreY;
  late final double taglineTop;
}

double _interval(
  double t,
  double begin,
  double end, [
  Curve curve = Curves.linear,
]) => curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

class _SplashPainter extends CustomPainter {
  _SplashPainter({
    required this.t,
    required this.idle,
    required this.ink,
    required this.fragments,
    required this.layout,
  });

  final double t;
  final double? idle;
  final Color ink;
  final List<TextPainter> fragments;
  final _Layout layout;

  static const _blue = NexBrand.blue;

  Offset get _eyes => (NexBrand.blueEye + NexBrand.inkEye) / 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    final markY =
        layout.finalMarkY * _interval(t, .58, .72, Curves.easeInOutCubic);
    final centre = NexBrand.markBounds.center;
    Offset toScreen(Offset p) =>
        (p - centre) * layout.markScale + Offset(0, markY);

    _paintMark(canvas, markY);
    for (final (index, fragment) in _fragments.indexed) {
      _paintFragment(canvas, fragment, fragments[index], toScreen);
    }
    _paintWordmark(canvas);
  }

  void _paintMark(Canvas canvas, double markY) {
    final bounds = NexBrand.markBounds;
    canvas
      ..save()
      ..translate(0, markY)
      ..scale(layout.markScale)
      ..translate(-bounds.center.dx, -bounds.center.dy);

    // The body grows out of the eyes: a circle opening from between them.
    final reveal = _interval(t, .06, .42, Curves.easeOutCubic);
    final reach = _farthest(bounds, _eyes);
    if (reveal > 0) {
      final radius = reach * reveal;
      canvas
        ..save()
        ..clipPath(
          Path()..addOval(Rect.fromCircle(center: _eyes, radius: radius)),
        );
      final inkPaint = Paint()..color = ink;
      canvas
        ..drawPath(NexBrand.body, inkPaint)
        ..drawPath(NexBrand.leftArm, inkPaint)
        ..drawPath(NexBrand.blueArm, Paint()..color = _blue)
        ..restore();
      if (reveal < 1) {
        canvas.drawCircle(
          _eyes,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 / layout.markScale
            ..color = _blue.withValues(alpha: .3 * (1 - reveal)),
        );
      }
    }

    if (idle case final pulse?) {
      canvas.drawCircle(
        _eyes,
        30 + 60 * Curves.easeOut.transform(pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / layout.markScale
          ..color = _blue.withValues(alpha: .28 * (1 - pulse)),
      );
    }

    // The eyes are there from the first frame; the blue one blinks.
    final blink = 1 - .9 * math.sin(math.pi * _interval(t, .02, .1));
    const r = NexBrand.eyeRadius;
    canvas
      ..drawOval(
        Rect.fromCenter(
          center: NexBrand.blueEye,
          width: 2 * r,
          height: 2 * r * blink,
        ),
        Paint()..color = _blue,
      )
      ..drawCircle(NexBrand.inkEye, r, Paint()..color = ink)
      ..restore();
  }

  void _paintFragment(
    Canvas canvas,
    _Fragment fragment,
    TextPainter glyph,
    Offset Function(Offset) toScreen,
  ) {
    final u = ((t - fragment.start) / _fragmentSpan).clamp(0.0, 1.0);
    if (u <= 0 || u >= 1) return;
    final anchor = toScreen(fragment.anchor);
    final outward = fragment.anchor - NexBrand.markBounds.center;
    final from = anchor + outward / outward.distance * 44;

    // A thread drawn from the fragment to the arm that will catch it.
    final thread = _interval(u, .15, .45, Curves.easeOut);
    final threadFade = 1 - _interval(u, .6, .85);
    if (thread > 0 && threadFade > 0) {
      canvas.drawLine(
        from,
        Offset.lerp(from, anchor, thread)!,
        Paint()
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round
          ..color = ink.withValues(alpha: .3 * threadFade),
      );
    }

    // The fragment itself: it appears, then is pulled in along the thread.
    final appear = _interval(u, 0, .2, Curves.easeOut);
    final travel = _interval(u, .4, .7, Curves.easeInCubic);
    final opacity = appear * (1 - travel) * .85;
    if (opacity > 0) {
      final scale = (.6 + .4 * appear) * (1 - .7 * travel);
      final at = Offset.lerp(from, anchor, travel)!;
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..scale(scale)
        ..saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
      glyph.paint(canvas, Offset(-glyph.width / 2, -glyph.height / 2));
      canvas
        ..restore()
        ..restore();
    }

    // Where it joins, a ripple.
    final ripple = _interval(u, .65, 1, Curves.easeOut);
    if (ripple > 0) {
      canvas.drawCircle(
        anchor,
        2 + 9 * ripple,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = _blue.withValues(alpha: .8 * (1 - ripple)),
      );
    }
  }

  void _paintWordmark(Canvas canvas) {
    if (t < .66) return;
    final bounds = NexBrand.wordBounds;
    final scale = layout.wordScale;
    canvas
      ..save()
      ..translate(0, layout.wordCentreY)
      ..scale(scale)
      ..translate(-bounds.center.dx, -bounds.center.dy);

    void rise(Path path, double begin, double end, Color color) {
      final a = _interval(t, begin, end, Curves.easeOutCubic);
      if (a <= 0) return;
      canvas
        ..save()
        ..translate(0, (1 - a) * 10 / scale)
        ..drawPath(path, Paint()..color = color.withValues(alpha: a))
        ..restore();
    }

    rise(NexBrand.wordN, .66, .78, ink);
    rise(NexBrand.wordE, .69, .81, ink);
    rise(NexBrand.wordX, .72, .84, ink);

    // The blue stroke sweeps in along its own direction.
    final sweep = _interval(t, .74, .88, Curves.easeInOutCubic);
    if (sweep > 0) {
      final box = NexBrand.swoosh.getBounds();
      canvas
        ..save()
        ..clipRect(
          Rect.fromLTWH(box.left, box.top, box.width * sweep, box.height),
        )
        ..drawPath(NexBrand.swoosh, Paint()..color = _blue)
        ..restore();
    }

    // And the dot drops into place.
    final drop = _interval(t, .82, .97, Curves.bounceOut);
    if (t >= .82) {
      canvas.drawCircle(
        NexBrand.dot.translate(0, -(1 - drop) * 90),
        NexBrand.dotRadius,
        Paint()..color = _blue,
      );
    }
    canvas.restore();
  }

  static double _farthest(Rect rect, Offset from) => [
    rect.topLeft,
    rect.topRight,
    rect.bottomLeft,
    rect.bottomRight,
  ].map((corner) => (corner - from).distance).reduce(math.max);

  @override
  bool shouldRepaint(_SplashPainter old) =>
      old.t != t || old.idle != idle || old.ink != ink;
}
