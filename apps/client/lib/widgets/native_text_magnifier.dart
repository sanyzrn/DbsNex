import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Geometry adapter for the stock Flutter text loupe, not a second editor.
/// The native layout supplies coordinates in logical pixels relative to the
/// platform view. Text, selection, shaping and scrolling stay on Android.
class NexNativeTextMagnifier with WidgetsBindingObserver {
  final _controller = MagnifierController();
  final _info = ValueNotifier(MagnifierInfo.empty);
  bool _disposed = false;

  NexNativeTextMagnifier() {
    WidgetsBinding.instance.addObserver(this);
  }

  void update({
    required BuildContext context,
    required RenderBox? source,
    required Map<String, Object?> geometry,
    required bool enabled,
  }) {
    if (_disposed) return;
    if (!enabled ||
        geometry['show'] != true ||
        source == null ||
        !source.attached ||
        !source.hasSize ||
        ModalRoute.isCurrentOf(context) == false ||
        Overlay.maybeOf(context) == null) {
      hide();
      return;
    }
    double? number(String key) {
      final value = geometry[key];
      if (value is! num || !value.isFinite) return null;
      return value.toDouble();
    }

    final x = number('x');
    final caretX = number('caretX');
    final top = number('top');
    final bottom = number('bottom');
    final left = number('left');
    final right = number('right');
    final width = number('width');
    final height = number('height');
    if (x == null ||
        caretX == null ||
        top == null ||
        bottom == null ||
        left == null ||
        right == null ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        bottom <= top ||
        right < left ||
        bottom <= 0 ||
        top >= height) {
      hide();
      return;
    }
    final screen = MediaQuery.sizeOf(context);
    final visibleScreen = Rect.fromLTRB(
      0,
      MediaQuery.paddingOf(context).top,
      screen.width,
      math.max(0, screen.height - MediaQuery.viewInsetsOf(context).bottom),
    );
    final field = MatrixUtils.transformRect(
      source.getTransformTo(null),
      Rect.fromLTWH(0, 0, width, height),
    ).intersect(visibleScreen);
    if (field.isEmpty) {
      hide();
      return;
    }
    final line = MatrixUtils.transformRect(
      source.getTransformTo(null),
      Rect.fromLTRB(left, top, right, bottom),
    );
    final caret = MatrixUtils.transformRect(
      source.getTransformTo(null),
      Rect.fromLTWH(caretX, top, 1, bottom - top),
    );
    _info.value = MagnifierInfo(
      globalGesturePosition: source.localToGlobal(
        Offset(x, (top + bottom) / 2),
      ),
      caretRect: caret,
      fieldBounds: field,
      currentLineBoundaries: line,
    );
    if (!_controller.shown) {
      unawaited(
        _controller.show(
          context: context,
          builder: (_) => IgnorePointer(
            child: ExcludeSemantics(
              child: Stack(
                children: [
                  TextMagnifier(
                    key: const ValueKey('native-text-magnifier'),
                    magnifierInfo: _info,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  void hide() => unawaited(_controller.hide());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) hide();
  }

  @override
  void didChangeMetrics() => hide();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    hide();
    _info.dispose();
  }
}
