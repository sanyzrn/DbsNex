import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/vault_session.dart';

/// Builds with whether the private tools are unlocked right now, and again
/// the moment that changes — when an unlock begins, when it is closed, and
/// when it runs out on its own.
///
/// For the lock on a private tool's card, which opens with the unlock and
/// closes again with it: it was a closed lock throughout, so nothing on the
/// Tools page or the home screen said that the fingerprint would not be
/// asked for again.
class VaultOpenBuilder extends StatefulWidget {
  const VaultOpenBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool open) builder;

  @override
  State<VaultOpenBuilder> createState() => _VaultOpenBuilderState();
}

class _VaultOpenBuilderState extends State<VaultOpenBuilder>
    with WidgetsBindingObserver {
  final _session = VaultSession.instance;
  Timer? _lapse;

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _watch();
  }

  /// An unlock that runs out says nothing, so this waits it out. A touch
  /// inside a private tool pushes the deadline on; the timer then finds it
  /// still open and waits again.
  void _watch() {
    _lapse?.cancel();
    _lapse = _session.isOpen
        ? Timer(_session.remaining + const Duration(milliseconds: 50), _changed)
        : null;
  }

  void _changed() {
    if (!mounted) return;
    setState(_watch);
  }

  // Timers do not always run while the app is away; coming back is a moment
  // to look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _changed();
  }

  @override
  void dispose() {
    _lapse?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _session.isOpen);
}

/// The lock on a private tool's card: open while the private tools are.
IconData nexLockBadge({required bool open}) =>
    open ? Icons.lock_open_rounded : Icons.lock_rounded;
