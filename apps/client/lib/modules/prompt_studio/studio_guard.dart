import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'studio_strings.dart';

class StudioGuard extends StatefulWidget {
  const StudioGuard({
    super.key,
    required this.draft,
    required this.busy,
    required this.child,
  });
  final NexModuleFormDraft draft;
  final bool Function() busy;
  final Widget child;
  @override
  State<StudioGuard> createState() => _StudioGuardState();
}

class _StudioGuardState extends State<StudioGuard> {
  bool _leaving = false;
  Future<void> _back() async {
    if (_leaving || widget.busy()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _leaving = true);
    if (!await widget.draft.finish()) {
      widget.draft.resume();
      if (mounted) {
        setState(() => _leaving = false);
        nexShowBanner(
          context,
          message: studioStrings(context, 'saveError'),
          kind: NexBannerKind.failed,
        );
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (popped, _) {
      if (!popped) unawaited(_back());
    },
    child: AbsorbPointer(absorbing: _leaving, child: widget.child),
  );
}
