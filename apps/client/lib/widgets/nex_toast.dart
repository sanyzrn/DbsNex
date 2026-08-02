import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// A [SnackBar] whose content pops in via [NexToastPop] instead of only
/// fading. Every toast in the app is built through this rather than
/// [SnackBar] directly, so the flourish is universal without being repeated
/// at each call site.
SnackBar nexToast({
  required Widget content,
  Duration duration = const Duration(milliseconds: 4000),
  SnackBarAction? action,
}) => SnackBar(
  content: NexToastPop(child: content),
  duration: duration,
  action: action,
);
