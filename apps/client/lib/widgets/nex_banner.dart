import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

/// Which mark a banner leads with.
///
/// Three, not one per message. The icon is there to say *what kind of thing
/// happened* at a glance — done, undone, something the app did on its own —
/// and a fourth shade of that is a distinction nobody reads.
enum NexBannerKind {
  /// Something the user asked for, and it worked.
  done,

  /// Something did not work. Never red: a toast that cannot be acted on is
  /// information, and painting it as an alarm makes every failed copy feel
  /// like data loss.
  failed,

  /// The intelligence layer, or anything else the app did unprompted.
  ai,
}

/// A notification that arrives from the top of the screen, as a capsule that
/// drips out of the top edge and is drawn back into it when it goes.
///
/// Replaces a bottom SnackBar, and the position is the point: on a phone the
/// bottom of the screen is where this app's own controls live — the capture
/// button, the send arrow, a sheet's primary action — so a message that lands
/// there covers the thing you were about to press. It also arrives where the
/// system's own notifications do, which is where people already look.
///
/// Shown through an [OverlayEntry] rather than a [ScaffoldMessenger]: a
/// SnackBar cannot be positioned at the top, and a MaterialBanner pushes the
/// page's content down instead of passing over it.
///
/// One at a time. A second call replaces the first rather than queueing, since
/// a queue means the message you are reading is about something you did
/// several actions ago.
void nexShowBanner(
  BuildContext context, {
  required String message,
  NexBannerKind kind = NexBannerKind.done,
  String? actionLabel,
  VoidCallback? onAction,
  bool haptics = true,
}) => NexBannerHost.of(context)?.show(
  message: message,
  kind: kind,
  actionLabel: actionLabel,
  onAction: onAction,
  haptics: haptics,
);

/// A handle to the overlay a banner will be shown in, captured before an
/// `await` so the call after it does not need a [BuildContext].
///
/// Exactly the shape the call sites already used with `ScaffoldMessenger.of`,
/// and for the same reason: reaching for a context across a suspension is the
/// bug `use_build_context_synchronously` exists to catch, and half the
/// messages in this app are raised after some work finished.
class NexBannerHost {
  const NexBannerHost._(this._overlay);

  final OverlayState _overlay;

  /// Null when there is no overlay to show in — a widget built outside a
  /// Navigator, which happens in tests.
  static NexBannerHost? of(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    return overlay == null ? null : NexBannerHost._(overlay);
  }

  void show({
    required String message,
    NexBannerKind kind = NexBannerKind.done,
    String? actionLabel,
    VoidCallback? onAction,
    bool haptics = true,
  }) {
    if (!_overlay.mounted) return;
    _show(
      _overlay,
      message: message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      haptics: haptics,
    );
  }
}

void _show(
  OverlayState overlay, {
  required String message,
  required NexBannerKind kind,
  required String? actionLabel,
  required VoidCallback? onAction,
  required bool haptics,
}) {
  _current?.remove();
  _current = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _NexBanner(
      message: message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      haptics: haptics,
      onDismissed: () {
        // Only while it is still the one showing. A newer banner (or
        // [nexHideBanner]) has already removed it otherwise, and its exit
        // animation can still finish in the frame before it is unmounted —
        // removing it a second time is an assertion, which is what an action
        // that shows a follow-up banner ran into.
        if (_current != entry) return;
        _current = null;
        entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

/// The banner on screen right now, if any — see the one-at-a-time note above.
OverlayEntry? _current;

/// Removes whatever banner is showing. Called when a screen that raised one
/// goes away, so a message cannot outlive the thing it was about.
void nexHideBanner() {
  _current?.remove();
  _current = null;
}

class _NexBanner extends StatefulWidget {
  const _NexBanner({
    required this.message,
    required this.kind,
    required this.actionLabel,
    required this.onAction,
    required this.haptics,
    required this.onDismissed,
  });

  final String message;
  final NexBannerKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool haptics;
  final VoidCallback onDismissed;

  @override
  State<_NexBanner> createState() => _NexBannerState();
}

class _NexBannerState extends State<_NexBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
    reverseDuration: const Duration(milliseconds: 420),
  );

  Timer? _timer;
  bool _leaving = false;

  /// Longer when there is something to press. Four seconds is enough to read a
  /// confirmation; it is not enough to notice a delete, decide against it, and
  /// reach the Undo.
  Duration get _life => widget.actionLabel == null
      ? const Duration(milliseconds: 3400)
      : const Duration(milliseconds: 6000);

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // The vibration is half of what makes this read as an arrival rather than
    // as something that was always there. Gated on the same preference as
    // every other haptic in the app.
    if (widget.haptics) HapticFeedback.mediumImpact();
    _timer = Timer(_life, _dismiss);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.accessibleNavigationOf(context) &&
        widget.actionLabel != null) {
      _timer?.cancel();
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.duration = Duration.zero;
      _controller.reverseDuration = Duration.zero;
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  void _act() {
    // The action runs before the exit animation, not after it: an Undo that
    // waits for a slide-out is an Undo that looks like it missed.
    widget.onAction?.call();
    unawaited(_dismiss());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    // A capsule of its own colour in both themes, the way One UI's pop-ups
    // and the island they grow from are: near-black on a light page, a lifted
    // graphite on a dark one, where black would disappear into the page.
    final capsule = dark ? const Color(0xFF2C2E33) : const Color(0xFF17181B);
    final accent = dark ? scheme.primary : scheme.inversePrimary;
    final top = MediaQuery.paddingOf(context).top;
    const gap = NexSpacing.sm;

    final message = Semantics(
      liveRegion: true,
      child: Text(
        widget.message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final action = widget.actionLabel == null
        ? null
        : TextButton(
            onPressed: _act,
            style: TextButton.styleFrom(
              foregroundColor: accent,
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(widget.actionLabel!),
          );

    return Positioned(
      top: top + gap,
      left: NexSpacing.md,
      right: NexSpacing.md,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, minWidth: 140),
          child: GestureDetector(
            onTap: _dismiss,
            // Up, not down. A downward flick is how a phone opens the
            // notification shade, and this is sitting exactly where that
            // gesture starts.
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -80) {
                unawaited(_dismiss());
              }
            },
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;
                return CustomPaint(
                  painter: _CapsulePainter(
                    t: t,
                    color: capsule,
                    // From the capsule's top edge to the top of the screen:
                    // where the island it drips from sits.
                    lift: top + gap,
                    hairline: Colors.white.withValues(alpha: dark ? .08 : 0),
                  ),
                  child: Opacity(
                    opacity: _CapsulePainter.span(t, .55, .9),
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  10,
                  NexSpacing.sm,
                  14,
                  NexSpacing.sm,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (MediaQuery.textScalerOf(context).scale(1) > 1.4 ||
                        constraints.maxWidth < 260) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [message, ?action],
                      );
                    }
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Glyph(kind: widget.kind, accent: accent),
                        const SizedBox(width: 10),
                        Flexible(child: message),
                        if (action != null) ...[
                          const SizedBox(width: NexSpacing.xs),
                          action,
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The capsule and the drop it arrives as.
///
/// Out of a small island at the top of the screen — roughly where the camera
/// sits — a drop falls on a thread of liquid, lands where the capsule goes and
/// spreads sideways into it; the thread thins and lets go of the island. The
/// exit is the same film run backwards, so the capsule is drawn back up into
/// the edge it came from. The gooey pass runs only while that is happening;
/// at rest this is one rounded rectangle and a shadow.
class _CapsulePainter extends CustomPainter {
  _CapsulePainter({
    required this.t,
    required this.color,
    required this.lift,
    required this.hairline,
  });

  final double t;
  final Color color;
  final double lift;
  final Color hairline;

  static double span(double t, double a, double b, [Curve c = Curves.linear]) =>
      c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(math.min(size.height / 2, 28));
    final full = RRect.fromRectAndRadius(Offset.zero & size, radius);
    if (t >= 1) {
      canvas.drawShadow(Path()..addRRect(full), Colors.black, 6, false);
      canvas.drawRRect(full, Paint()..color = color);
      if (hairline.a > 0) {
        canvas.drawRRect(
          full.deflate(0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = hairline,
        );
      }
      return;
    }
    final cx = size.width / 2;
    final h = size.height;
    final fall = span(t, 0, .4, Curves.easeOutCubic);
    final spread = span(t, .28, .72, Curves.easeOutBack);
    final letGo = span(t, .3, .6, Curves.easeInCubic);
    final island = Offset(cx, -lift + 4);
    final dropCenter = Offset(cx, ui.lerpDouble(-lift + 10, h / 2, fall)!);
    final dropRadius = ui.lerpDouble(8, h / 2, fall)!;
    final width = ui.lerpDouble(dropRadius * 2, size.width, spread)!;
    final capsule = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: dropCenter,
        width: math.max(width, 1),
        height: dropRadius * 2,
      ),
      Radius.circular(math.min(dropRadius, radius.x)),
    );
    final thread = ui.lerpDouble(7, 0, letGo)!;
    nexPaintGooey(
      canvas,
      bounds: Rect.fromLTRB(-24, -lift - 30, size.width + 24, h + 24),
      color: color,
      softness: 6,
      shapes: [
        nexGooeyCircle(island, ui.lerpDouble(16, 0, letGo)!),
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - thread, island.dy, cx + thread, dropCenter.dy),
          Radius.circular(thread),
        ),
        capsule,
      ],
    );
  }

  @override
  bool shouldRepaint(_CapsulePainter old) =>
      old.t != t ||
      old.color != color ||
      old.lift != lift ||
      old.hairline != hairline;
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.kind, required this.accent});

  final NexBannerKind kind;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      NexBannerKind.done => Icons.check_rounded,
      NexBannerKind.failed => Icons.priority_high_rounded,
      NexBannerKind.ai => Icons.auto_awesome,
    };
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.22),
      ),
      child: Icon(icon, size: 18, color: accent),
    );
  }
}
