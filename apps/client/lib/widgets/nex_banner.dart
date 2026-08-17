import 'dart:async';

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

/// A notification that arrives from the top of the screen.
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
        if (_current == entry) _current = null;
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
    duration: NexMotion.slow,
    reverseDuration: NexMotion.standard,
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.sm,
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              // easeOutBack on the way in gives the small overshoot that makes
              // it land rather than stop. Not on the way out — a banner that
              // bounces as it leaves reads as a bug.
              final eased = _leaving || reduceMotion
                  ? t
                  : Curves.easeOutBack.transform(t);
              return Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: FractionalTranslation(
                  translation: Offset(0, reduceMotion ? 0 : eased - 1),
                  child: child,
                ),
              );
            },
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
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
                  child: Material(
                    color: scheme.surfaceContainerHighest,
                    elevation: 8,
                    shadowColor: scheme.shadow.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(NexRadius.xl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NexSpacing.md,
                        vertical: NexSpacing.sm + 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(NexRadius.xl),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Glyph(kind: widget.kind),
                          const SizedBox(width: NexSpacing.sm),
                          Flexible(
                            child: Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (widget.actionLabel != null) ...[
                            const SizedBox(width: NexSpacing.sm),
                            TextButton(
                              onPressed: _act,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: NexSpacing.sm,
                                ),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(widget.actionLabel!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.kind});

  final NexBannerKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (kind) {
      NexBannerKind.done => Icons.check_circle_outline,
      NexBannerKind.failed => Icons.error_outline,
      NexBannerKind.ai => Icons.auto_awesome,
    };
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primary.withValues(alpha: 0.16),
      ),
      child: Icon(icon, size: 16, color: scheme.primary),
    );
  }
}
