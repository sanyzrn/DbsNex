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
/// One at a time — with one exception. A plain banner arriving while an
/// actionable one is still up does not replace it: the Undo it is carrying is
/// a promise with a countdown, and swallowing it to say "Saved" is trading
/// something the user might need for something they can guess. The plain
/// banner waits its turn instead, and shows when the actionable one leaves.
/// Everything else still replaces what came before — a queue of receipts
/// would mean the message you are reading is about something you did several
/// actions ago. A replaced banner is drawn back into the edge it came from
/// rather than vanishing mid-sentence: the exit animation always runs.
///
/// Returns a [NexBannerHandle] naming the banner this call put up, so a
/// screen whose promise expires with it — an Undo that only works while the
/// page is alive — can take that one banner down when it goes, without
/// reaching for [nexHideBanner] and whatever unrelated banner is showing by
/// then. Ignoring the return value shows the banner exactly as before.
NexBannerHandle? nexShowBanner(
  BuildContext context, {
  required String message,
  NexBannerKind kind = NexBannerKind.done,
  String? actionLabel,
  VoidCallback? onAction,
  Key? actionKey,
  Duration? duration,
  bool haptics = true,
}) => NexBannerHost.of(context)?.show(
  message: message,
  kind: kind,
  actionLabel: actionLabel,
  onAction: onAction,
  actionKey: actionKey,
  duration: duration,
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

  bool get mounted => _overlay.mounted;
  BuildContext get context => _overlay.context;

  /// Null when there is no overlay to show in — a widget built outside a
  /// Navigator, which happens in tests.
  static NexBannerHost? of(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    return overlay == null ? null : NexBannerHost._(overlay);
  }

  NexBannerHandle? show({
    required String message,
    NexBannerKind kind = NexBannerKind.done,
    String? actionLabel,
    VoidCallback? onAction,
    Key? actionKey,
    Duration? duration,
    bool haptics = true,
  }) {
    if (!_overlay.mounted) return null;
    return _show(
      _overlay,
      message: message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      actionKey: actionKey,
      duration: duration,
      haptics: haptics,
    );
  }
}

NexBannerHandle _show(
  OverlayState overlay, {
  required String message,
  required NexBannerKind kind,
  required String? actionLabel,
  required VoidCallback? onAction,
  required Key? actionKey,
  required Duration? duration,
  required bool haptics,
}) {
  final current = _current;
  final actionable = actionLabel != null;

  // An actionable banner that is still up keeps its place: only another
  // actionable banner may take it, because only another one is carrying a
  // promise of the same weight. A plain receipt — "Saved", "Copied" — waits
  // behind it rather than eating the Undo a finger might still be travelling
  // toward. At most one waits: a newer plain banner replaces a queued one,
  // exactly as shown banners replace each other.
  if (current != null &&
      current.actionable &&
      !current.leaving &&
      !actionable) {
    _pending = _PendingBanner(
      overlay,
      message: message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      actionKey: actionKey,
      duration: duration,
      haptics: haptics,
    );
    return NexBannerHandle._waiting(_pending!);
  }

  // Whatever else is up makes way — with its exit animation, not by
  // vanishing. The capsule is drawn back into the edge it dripped from while
  // the new one drips out of it.
  _retire(current);
  return _insert(
    overlay,
    message: message,
    kind: kind,
    actionLabel: actionLabel,
    onAction: onAction,
    actionKey: actionKey,
    duration: duration,
    haptics: haptics,
  );
}

/// The banner on screen right now, if any — see the one-at-a-time note on
/// [nexShowBanner].
_BannerSession? _current;

/// The one plain banner waiting behind an actionable one, if any. One slot,
/// newest wins: a queue of stale receipts is worse than a dropped one.
_PendingBanner? _pending;

/// Begins a session's exit. With an animation when there is anything on
/// screen to animate — the capsule is sucked back into the top edge — and
/// instantly when the entry was never built, which is two banners in one
/// frame.
void _retire(_BannerSession? session) {
  if (session == null || session.leaving) return;
  session.leaving = true;
  final state = session.state;
  if (state != null) {
    unawaited(state._dismiss());
  } else {
    session.remove();
  }
}

NexBannerHandle _insert(
  OverlayState overlay, {
  required String message,
  required NexBannerKind kind,
  required String? actionLabel,
  required VoidCallback? onAction,
  required Key? actionKey,
  required Duration? duration,
  required bool haptics,
}) {
  final session = _BannerSession(actionable: actionLabel != null);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _NexBanner(
      session: session,
      message: message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      actionKey: actionKey,
      duration: duration,
      haptics: haptics,
      onGone: () {
        // Called once, after the exit animation has finished (or instantly,
        // for a banner that never animated): the entry leaves the overlay
        // here and only here, so nothing removes it twice. The module state
        // moves on only if this is still the showing session — a replacement
        // has already taken the slot, and a hidden one has cleaned up itself.
        session.remove();
        if (identical(_current, session)) {
          _current = null;
          _drainPending();
        }
      },
    ),
  );
  session.entry = entry;
  _current = session;
  overlay.insert(entry);
  return NexBannerHandle._(session);
}

/// Shows the banner that was waiting, if any — called when the banner ahead
/// of it is gone for good.
void _drainPending() {
  final pending = _pending;
  if (pending == null) return;
  _pending = null;
  if (!pending.overlay.mounted) return;
  _insert(
    pending.overlay,
    message: pending.message,
    kind: pending.kind,
    actionLabel: pending.actionLabel,
    onAction: pending.onAction,
    actionKey: pending.actionKey,
    duration: pending.duration,
    haptics: pending.haptics,
  );
}

/// A banner that is up or on its way up, from the module's point of view.
class _BannerSession {
  _BannerSession({required this.actionable});

  /// Whether the banner carries an action whose window dies with the banner.
  final bool actionable;

  /// Set once the banner starts leaving, by whoever started it — its own
  /// timer, a tap, or a replacement — so a plain banner arriving during the
  /// exit animation takes the slot instead of queueing behind a ghost.
  bool leaving = false;

  late final OverlayEntry entry;
  _NexBannerState? state;
  final closed = Completer<void>();
  bool _removed = false;

  void remove() {
    if (_removed) return;
    _removed = true;
    entry.remove();
    if (!closed.isCompleted) closed.complete();
  }
}

/// The parameters of a banner waiting for its turn, held as-is so what shows
/// later is exactly what was asked for then.
class _PendingBanner {
  _PendingBanner(
    this.overlay, {
    required this.message,
    required this.kind,
    required this.actionLabel,
    required this.onAction,
    required this.actionKey,
    required this.duration,
    required this.haptics,
  });

  final OverlayState overlay;
  final String message;
  final NexBannerKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;
  final Duration? duration;
  final bool haptics;
}

/// The one banner a specific [nexShowBanner] call put up.
///
/// [hide] is a no-op once that banner has already gone — dismissed, acted
/// on, or replaced by a newer one — so taking down an expired promise can
/// never take down somebody else's message with it. For a banner still
/// waiting behind an actionable one, [hide] takes it out of the queue, and
/// [isShowing] reads false until it is actually up.
class NexBannerHandle {
  NexBannerHandle._(this._session) : _waiting = null;

  NexBannerHandle._waiting(this._waiting) : _session = null;

  final _BannerSession? _session;
  final _PendingBanner? _waiting;

  /// Completes after an inserted banner leaves the overlay. Queued plain
  /// banners have no action window and return null.
  Future<void>? get closed => _session?.closed.future;

  bool get isShowing => _session != null && identical(_current, _session);

  void hide() {
    final waiting = _waiting;
    if (waiting != null) {
      if (identical(_pending, waiting)) _pending = null;
      return;
    }
    final session = _session;
    if (session == null) return;
    if (identical(_current, session)) _current = null;
    session.remove();
  }
}

/// Removes whatever banner is showing — and whatever is waiting behind it,
/// since a message cannot outlive the thing it was about either. Called when
/// a screen that raised one goes away.
void nexHideBanner() {
  final current = _current;
  _current = null;
  _pending = null;
  current?.remove();
}

class _NexBanner extends StatefulWidget {
  const _NexBanner({
    required this.session,
    required this.message,
    required this.kind,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
    this.duration,
    required this.haptics,
    required this.onGone,
  });

  final _BannerSession session;
  final String message;
  final NexBannerKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;
  final Duration? duration;
  final bool haptics;
  final VoidCallback onGone;

  @override
  State<_NexBanner> createState() => _NexBannerState();
}

class _NexBannerState extends State<_NexBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // The drip-in used to take 720ms — longer than a page transition, for a
    // message whose point is that it is already gone when you look up. The
    // drop-and-spread choreography is unchanged; it just happens in half the
    // time, so the words land with the motion instead of after it.
    duration: const Duration(milliseconds: 360),
    reverseDuration: const Duration(milliseconds: 420),
  );

  Timer? _timer;
  bool _leaving = false;

  /// Set while a finger is holding the banner: the countdown is paused,
  /// because the one person still reading it is the one holding it.
  bool _holding = false;

  /// The milliseconds of life left, from the last scheduling. Updated when
  /// the banner is paused so resuming continues the countdown rather than
  /// starting it over.
  int _lifeMs = 0;

  /// How long the banner stays. Given outright by callers who know better —
  /// a module's retry window — and otherwise earned: 45ms a character, so a
  /// message is gone roughly when it has been read, clamped to a floor that
  /// is long enough to notice and a ceiling that stops a banner camping on
  /// the screen. An actionable banner gets two more seconds: noticing a
  /// delete, deciding against it and reaching the Undo takes longer than
  /// reading "Saved".
  Duration get _life {
    final given = widget.duration;
    if (given != null) return given;
    final read = (1200 + 45 * widget.message.length).clamp(2200, 6500);
    final reach = widget.actionLabel == null ? 0 : 2000;
    return Duration(milliseconds: read + reach);
  }

  @override
  void initState() {
    super.initState();
    widget.session.state = this;
    // The countdown belongs to the banner at rest, not to the banner still
    // arriving: it used to start in initState, so the entrance ate six
    // hundred of a plain banner's milliseconds before there was anything to
    // read. The status listener fires only on a real completion — a reverse
    // called mid-entrance never reaches it, and a replaced banner has no
    // life left to start.
    _controller.addStatusListener(_onStatus);
    _controller.forward();
    // The vibration is half of what makes this read as an arrival rather than
    // as something that was always there. Gated on the same preference as
    // every other haptic in the app.
    if (widget.haptics) HapticFeedback.mediumImpact();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _startLife();
  }

  // Overlay entries can retain an older inherited MediaQuery when the OS
  // accessibility setting changes without navigating. Read the live platform
  // state as well: an actionable Undo must never expire under screen readers.
  bool get _keepActionUntilDismissed =>
      widget.actionLabel != null &&
      (MediaQuery.accessibleNavigationOf(context) ||
          WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
              .accessibleNavigation);

  void _startLife() {
    if (_leaving || !mounted) return;
    if (_keepActionUntilDismissed) return;
    _scheduleLife(_life);
  }

  void _scheduleLife(Duration remaining) {
    _timer?.cancel();
    _lifeMs = remaining.inMilliseconds;
    _tickLife();
  }

  /// A one-shot Timer cannot report elapsed time before it fires; its tick
  /// remains zero, which incorrectly restarted a held Undo's entire lifetime.
  /// Small clock slices let a pause preserve the remaining time without
  /// relying on a frame timestamp (gestures can arrive between frames).
  void _tickLife() {
    if (_leaving || !mounted) return;
    if (_keepActionUntilDismissed) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_lifeMs <= 0) {
      unawaited(_dismiss());
      return;
    }
    final slice = math.min(_lifeMs, 100);
    _timer = Timer(Duration(milliseconds: slice), () {
      _lifeMs -= slice;
      _tickLife();
    });
  }

  void _pauseLife() {
    if (_holding || _timer == null) return;
    _holding = true;
    _timer!.cancel();
    _timer = null;
  }

  void _resumeLife() {
    if (!_holding) return;
    _holding = false;
    if (_leaving || !mounted) return;
    if (_keepActionUntilDismissed) return;
    _scheduleLife(Duration(milliseconds: _lifeMs));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_keepActionUntilDismissed) {
      _timer?.cancel();
      _timer = null;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.duration = Duration.zero;
      _controller.reverseDuration = Duration.zero;
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    widget.session.state = null;
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    // The module learns this the moment leaving begins, so a plain banner
    // arriving during the exit takes the slot instead of queueing behind a
    // capsule that is already on its way into the edge.
    widget.session.leaving = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onGone();
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
            key: widget.actionKey,
            onPressed: _act,
            style: TextButton.styleFrom(
              foregroundColor: accent,
              // Forty-eight tall, the app's own floor ([nexMinTapTarget]):
              // Undo is the most time-critical touch in the app — six
              // seconds and counting — and it sat at forty.
              minimumSize: const Size(48, 48),
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
            // Hold to keep it: the countdown pauses under the finger — an
            // Undo being thought about is an Undo still on the table. The
            // countdown continues where it left off, not from the top.
            onLongPressStart: (_) => _pauseLife(),
            onLongPressEnd: (_) => _resumeLife(),
            onLongPressCancel: _resumeLife,
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
                    // The words used to wait until the capsule was 55–90% of
                    // the way in — unreadable for most of an entrance whose
                    // whole job is to be read. They surface from 30% and are
                    // solid by two thirds.
                    opacity: _CapsulePainter.span(t, .3, .65),
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
