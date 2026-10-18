import 'package:flutter/painting.dart';

/// Keeps the platform's nonlinear accessibility curve at every font size.
class NexUiTextScaler extends TextScaler {
  const NexUiTextScaler(this.system, this.uiScale);
  final TextScaler system;
  final double uiScale;

  @override
  double scale(double fontSize) => system.scale(fontSize) * uiScale;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is NexUiTextScaler &&
      other.system == system &&
      other.uiScale == uiScale;

  @override
  int get hashCode => Object.hash(system, uiScale);
}
