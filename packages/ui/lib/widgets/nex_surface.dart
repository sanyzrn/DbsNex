import 'package:flutter/material.dart';

import '../tokens/nex_appearance.dart';
import '../tokens/nex_tokens.dart';

/// A bounded interactive panel. Its ink stays above the glass material.
class NexSurface extends StatelessWidget {
  const NexSurface({
    super.key,
    required this.child,
    required this.color,
    this.borderRadius = const BorderRadius.all(Radius.circular(NexRadius.lg)),
    this.border = BorderSide.none,
    this.clipBehavior = Clip.antiAlias,
    this.padding,
  });

  final Widget child;
  final Color color;
  final BorderRadius borderRadius;
  final BorderSide border;
  final Clip clipBehavior;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: borderRadius,
      side: border,
    );
    final body = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    if (!context.nexVisualStyle.liquidGlass) {
      return Material(
        color: color,
        shape: shape,
        clipBehavior: clipBehavior,
        child: body,
      );
    }
    return NexGlassSurface(
      blur: false,
      showShadow: false,
      borderRadius: borderRadius,
      fallbackColor: color,
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: clipBehavior,
        child: body,
      ),
    );
  }
}
