import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'form_draft.dart';
import 'gold_strings.dart';

/// Await the last checkpoint before the route leaves. This keeps a later
/// module-data deletion from racing a write issued after editor disposal.
class DraftGuard extends StatefulWidget {
  const DraftGuard({
    super.key,
    required this.drafts,
    required this.busy,
    required this.child,
  });
  final Iterable<FormDraft> Function() drafts;
  final bool Function() busy;
  final Widget child;
  @override
  State<DraftGuard> createState() => _DraftGuardState();
}

class _DraftGuardState extends State<DraftGuard> {
  bool _closing = false;
  Future<void> _leave() async {
    if (_closing || widget.busy()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _closing = true);
    final drafts = widget.drafts().toList();
    final saved = (await Future.wait(drafts.map((draft) => draft.finish())))
        .every((result) => result);
    if (!mounted) return;
    if (!saved) {
      for (final draft in drafts) {
        draft.resume();
      }
      setState(() => _closing = false);
      NexBannerHost.of(context)?.show(
        kind: NexBannerKind.failed,
        message: goldStrings(context, 'saveError'),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: AbsorbPointer(absorbing: _closing, child: widget.child),
  );
}
