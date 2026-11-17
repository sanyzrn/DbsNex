import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'security_strings.dart';

class AccountDraftGuard extends StatefulWidget {
  const AccountDraftGuard({
    super.key,
    required this.draft,
    required this.busy,
    required this.child,
  });
  final NexModuleFormDraft draft;
  final bool Function() busy;
  final Widget child;
  @override
  State<AccountDraftGuard> createState() => _AccountDraftGuardState();
}

class _AccountDraftGuardState extends State<AccountDraftGuard> {
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
          message: securityStrings(context, 'saveError'),
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
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_back());
    },
    child: AbsorbPointer(absorbing: _leaving, child: widget.child),
  );
}
