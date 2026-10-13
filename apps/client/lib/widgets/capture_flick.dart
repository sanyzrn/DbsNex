import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';

IconData captureShortcutIcon(CaptureShortcut shortcut) => switch (shortcut) {
  CaptureShortcut.none => Icons.add,
  CaptureShortcut.voice => Icons.mic_none,
  CaptureShortcut.camera => Icons.photo_camera_outlined,
  CaptureShortcut.checklist => Icons.checklist_rtl_outlined,
  CaptureShortcut.link => Icons.link_outlined,
  CaptureShortcut.gallery => Icons.photo_library_outlined,
  CaptureShortcut.file => Icons.insert_drive_file_outlined,
};

String captureShortcutLabel(AppLocalizations l10n, CaptureShortcut shortcut) =>
    switch (shortcut) {
      CaptureShortcut.none => l10n.captureFlickOff,
      CaptureShortcut.voice => l10n.voice,
      CaptureShortcut.camera => l10n.camera,
      CaptureShortcut.checklist => l10n.checklist,
      CaptureShortcut.link => l10n.link,
      CaptureShortcut.gallery => l10n.gallery,
      CaptureShortcut.file => l10n.file,
    };

/// The + button with a shortcut on each side: flicked left or right, it
/// starts that one thing straight away instead of opening the capture sheet.
///
/// A flick, not a mode. A button whose meaning was changed by an earlier
/// swipe and stayed changed would be a button nobody could trust at a
/// glance — a tap meant for a note would open the camera an hour later. So
/// the + is always the +; only a finger travelling sideways turns it, for as
/// long as it travels. The button leans after the finger, the + turns, and
/// once the travel is enough the shortcut's own glyph takes its place with a
/// tick, and a label above names what letting go will start. Letting go
/// before then, or bringing the finger back, puts the + back and starts
/// nothing.
///
/// Holding still is still the assistant (`NexLongPressGlow`), and a tap is
/// still the capture sheet: the three never share a gesture. A screen
/// reader is offered the two shortcuts as actions on the button.
class CaptureFlick extends StatefulWidget {
  const CaptureFlick({
    super.key,
    required this.preferences,
    required this.onShortcut,
    required this.builder,
  });

  final NexPreferences preferences;
  final ValueChanged<CaptureShortcut> onShortcut;

  /// The button, given the glyph to show in it.
  final Widget Function(BuildContext context, Widget glyph) builder;

  /// How far the finger travels before a side is armed.
  static const arm = 44.0;

  @override
  State<CaptureFlick> createState() => _CaptureFlickState();
}

class _CaptureFlickState extends State<CaptureFlick> {
  final _label = OverlayPortalController();
  final _anchor = LayerLink();

  /// How far the finger has travelled, signed: right is positive.
  double _dx = 0;

  /// What letting go now would start.
  CaptureShortcut? _armed;

  CaptureShortcut _side(double dx) => dx >= 0
      ? widget.preferences.captureFlickRight
      : widget.preferences.captureFlickLeft;

  bool get _anySide =>
      widget.preferences.captureFlickLeft != CaptureShortcut.none ||
      widget.preferences.captureFlickRight != CaptureShortcut.none;

  void _start(DragStartDetails details) {
    _label.show();
    setState(() {
      _dx = 0;
      _armed = null;
    });
  }

  void _update(DragUpdateDetails details) {
    final dx = (_dx + details.delta.dx).clamp(-160.0, 160.0);
    final side = _side(dx);
    final armed = dx.abs() >= CaptureFlick.arm && side != CaptureShortcut.none
        ? side
        : null;
    if (armed != null && armed != _armed && widget.preferences.haptics) {
      unawaited(HapticFeedback.selectionClick());
    }
    setState(() {
      _dx = dx;
      _armed = armed;
    });
  }

  void _end(DragEndDetails details) {
    var chosen = _armed;
    // A quick flick counts even when it was short: the speed says it was
    // meant, where a slow short drift does not.
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (chosen == null &&
        _dx.abs() >= CaptureFlick.arm / 3 &&
        velocity.abs() > 700 &&
        velocity.sign == _dx.sign) {
      final side = _side(_dx);
      if (side != CaptureShortcut.none) chosen = side;
    }
    _reset();
    if (chosen == null) return;
    if (widget.preferences.haptics) unawaited(HapticFeedback.mediumImpact());
    widget.onShortcut(chosen);
  }

  void _reset() {
    _label.hide();
    if (!mounted) return;
    setState(() {
      _dx = 0;
      _armed = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pop = NexMotion.of(context, NexMotion.pop);
    final travel = (_dx / CaptureFlick.arm).clamp(-1.0, 1.0);
    final armed = _armed;
    final glyph = AnimatedSwitcher(
      duration: pop,
      switchInCurve: NexMotion.popCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: armed == null
          // The + turns with the finger, an eighth of a turn at the point a
          // side arms — so it reads as about to become something else.
          ? Transform.rotate(
              key: const ValueKey('flick-plus'),
              angle: travel * math.pi / 4,
              child: const Icon(Icons.add, size: 32),
            )
          : Icon(
              captureShortcutIcon(armed),
              key: ValueKey('flick-${armed.name}'),
              size: 30,
            ),
    );
    final left = widget.preferences.captureFlickLeft;
    final right = widget.preferences.captureFlickRight;
    return Semantics(
      customSemanticsActions: {
        for (final shortcut in {left, right})
          if (shortcut != CaptureShortcut.none)
            CustomSemanticsAction(
              label: captureShortcutLabel(l10n, shortcut),
            ): () =>
                widget.onShortcut(shortcut),
      },
      child: OverlayPortal(
        controller: _label,
        overlayChildBuilder: (context) => _FlickLabel(
          anchor: _anchor,
          shortcut: _dx == 0 ? null : _side(_dx),
          toRight: _dx >= 0,
          armed: armed != null,
          reach: travel.abs(),
        ),
        child: CompositedTransformTarget(
          link: _anchor,
          child: GestureDetector(
            // From the touch itself, so the travel counted is the whole
            // movement and not what is left after the slop.
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: _anySide ? _start : null,
            onHorizontalDragUpdate: _anySide ? _update : null,
            onHorizontalDragEnd: _anySide ? _end : null,
            onHorizontalDragCancel: _anySide ? _reset : null,
            // The button leans after the finger, held back so it stays in
            // its place in the dock.
            child: Transform.translate(
              offset: Offset(_dx.clamp(-160.0, 160.0) * 0.18, 0),
              child: widget.builder(context, glyph),
            ),
          ),
        ),
      ),
    );
  }
}

/// Above the button while it is flicked: which way, and what letting go
/// will start — faint while travelling, solid once armed.
class _FlickLabel extends StatelessWidget {
  const _FlickLabel({
    required this.anchor,
    required this.shortcut,
    required this.toRight,
    required this.armed,
    required this.reach,
  });

  final LayerLink anchor;
  final CaptureShortcut? shortcut;
  final bool toRight;
  final bool armed;
  final double reach;

  @override
  Widget build(BuildContext context) {
    final shortcut = this.shortcut;
    if (shortcut == null || shortcut == CaptureShortcut.none) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ground = armed ? scheme.primary : scheme.inverseSurface;
    final ink = armed ? scheme.onPrimary : scheme.onInverseSurface;
    // East and west, not forward and back: those turn round in Persian, and
    // the flick does not.
    final arrow = Icon(toRight ? Icons.east : Icons.west, size: 16, color: ink);
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: anchor,
        targetAnchor: Alignment.topCenter,
        followerAnchor: Alignment.bottomCenter,
        offset: const Offset(0, -NexSpacing.sm),
        child: IgnorePointer(
          child: Opacity(
            opacity: (0.35 + 0.65 * reach).clamp(0.0, 1.0),
            child: AnimatedContainer(
              duration: NexMotion.of(context, NexMotion.fast),
              curve: NexMotion.curve,
              padding: const EdgeInsets.symmetric(
                horizontal: NexSpacing.md,
                vertical: NexSpacing.sm,
              ),
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                color: ground,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: TextDirection.ltr,
                children: [
                  if (!toRight) ...[
                    arrow,
                    const SizedBox(width: NexSpacing.xs),
                  ],
                  Icon(captureShortcutIcon(shortcut), size: 18, color: ink),
                  const SizedBox(width: NexSpacing.xs),
                  Text(
                    captureShortcutLabel(l10n, shortcut),
                    style: theme.textTheme.labelLarge?.copyWith(color: ink),
                  ),
                  if (toRight) ...[const SizedBox(width: NexSpacing.xs), arrow],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
