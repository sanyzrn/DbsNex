part of '../camera_sheet.dart';

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.black.withValues(alpha: .45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 48,
          child: IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
}

class _Shutter extends StatefulWidget {
  const _Shutter({
    required this.label,
    required this.holdLabel,
    required this.enabled,
    required this.recording,
    required this.onPressed,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final String label;

  /// Said to a screen reader, and shown under the dial: what a hold does.
  final String? holdLabel;

  final bool enabled;
  final bool recording;
  final VoidCallback onPressed;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;

  /// How long the finger rests before the hold becomes a recording. Short
  /// enough to feel like a hold, long enough that a tap is never one.
  static const holdAfter = Duration(milliseconds: 280);

  @override
  State<_Shutter> createState() => _ShutterState();
}

class _ShutterState extends State<_Shutter> {
  bool _down = false;
  bool _holding = false;
  Timer? _hold;
  Offset? _origin;

  void _press(PointerDownEvent event) {
    if (!widget.enabled) return;
    _origin = event.position;
    setState(() => _down = true);
    if (widget.onHoldStart == null) return;
    _hold = Timer(_Shutter.holdAfter, () {
      if (!mounted) return;
      _holding = true;
      widget.onHoldStart!();
    });
  }

  void _lift(PointerUpEvent event) {
    _hold?.cancel();
    _hold = null;
    if (!_down) return;
    setState(() => _down = false);
    if (_holding) {
      _holding = false;
      widget.onHoldEnd?.call();
      return;
    }
    // Moved off the dial before lifting: not a tap.
    final origin = _origin;
    if (origin != null && (event.position - origin).distance > 24) return;
    if (widget.enabled) widget.onPressed();
  }

  void _cancel(PointerCancelEvent event) {
    _hold?.cancel();
    _hold = null;
    if (!_down) return;
    setState(() => _down = false);
    if (_holding) {
      _holding = false;
      widget.onHoldEnd?.call();
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.enabled,
    label: widget.label,
    hint: widget.holdLabel,
    child: Listener(
      onPointerDown: _press,
      onPointerUp: _lift,
      onPointerCancel: _cancel,
      child: AnimatedScale(
        scale: _down ? .9 : 1,
        duration: NexMotion.of(context, NexMotion.fast),
        child: Container(
          width: 78,
          height: 78,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: .55),
            border: widget.recording
                ? Border.all(color: const Color(0xFFE5484D), width: 3)
                : null,
          ),
          child: AnimatedContainer(
            duration: NexMotion.of(context, NexMotion.fast),
            decoration: BoxDecoration(
              shape: widget.recording ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: widget.recording
                  ? BorderRadius.circular(NexRadius.sm)
                  : null,
              color: !widget.enabled
                  ? Colors.white54
                  : widget.recording
                  ? const Color(0xFFE5484D)
                  : Colors.white,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The red dot beside the clock. Still under reduce-motion.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: .35, end: 1).animate(_controller),
    child: Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFFE5484D),
        shape: BoxShape.circle,
      ),
    ),
  );
}

class _Menu extends StatelessWidget {
  const _Menu({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: .72),
    borderRadius: BorderRadius.circular(NexRadius.lg),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

/// What the panel has to say about the last recording.
enum _Notice { tooShort, tooLarge, failed }

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.md,
        vertical: 12,
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    ),
  );
}
