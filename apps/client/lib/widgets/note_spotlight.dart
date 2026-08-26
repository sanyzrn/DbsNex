import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// Says "this one" about a card, for a moment, and then stops.
///
/// Tapping a reminder used to open the app and leave you to find the note
/// yourself — the notification named it, and then the timeline showed the
/// same list it always shows. This is the answer to "which one was that":
/// a border in the accent that pulses twice around the card and fades.
///
/// A border rather than a flash of fill: fill would have to win against the
/// card's own colour in both themes and against whatever the note's tag dots
/// are doing, and a two-pixel outline reads at a glance without repainting
/// anything underneath it.
class NoteSpotlight extends StatefulWidget {
  const NoteSpotlight({
    super.key,
    required this.active,
    required this.onDone,
    required this.child,
  });

  final bool active;

  /// Called when the pulse is over, so the caller can forget which note it
  /// was for — otherwise the mark is permanent rather than momentary.
  final VoidCallback onDone;

  final Widget child;

  @override
  State<NoteSpotlight> createState() => _NoteSpotlightState();
}

class _NoteSpotlightState extends State<NoteSpotlight>
    with SingleTickerProviderStateMixin {
  /// Two pulses. One reads as a rendering glitch; three is a nag.
  static const _pulses = 2;
  static const _pulse = Duration(milliseconds: 620);

  // Built here rather than lazily, for the same reason CommitReceipt does:
  // every card but one is inactive and never touches the controller, which
  // would make `dispose` the first access — a ticker created against an
  // element that has already been deactivated.
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: _pulse);
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(NoteSpotlight old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
  }

  Future<void> _start() async {
    // After the frame, so a spotlight set while the list is still building
    // does not animate against a card that has not been laid out yet.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Still an answer, just an instantaneous one. The caller has to be told
      // either way or the id it holds is never released.
      widget.onDone();
      return;
    }
    for (var i = 0; i < _pulses; i++) {
      await _pulseController.forward(from: 0);
      if (!mounted) return;
      await _pulseController.reverse();
      if (!mounted) return;
    }
    widget.onDone();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        // Inside the card's own gutter, so the border sits on the card rather
        // than in the space between two of them.
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              padding: nexCardInsets,
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _pulseController,
                  curve: NexMotion.curve,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(NexRadius.lg),
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
