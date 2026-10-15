import 'dart:async';
import 'package:flutter/material.dart';
import 'form_draft.dart';
import 'words_strings.dart';

/// Await the last checkpoint before the route leaves. This keeps a later
/// module-data deletion from racing a write issued after editor disposal.
class DraftGuard extends StatefulWidget {
  const DraftGuard({
    super.key,
    required this.draft,
    required this.busy,
    required this.child,
  });
  final FormDraft draft;
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
    final saved = await widget.draft.finish();
    if (!mounted) return;
    if (!saved) {
      widget.draft.resume();
      setState(() => _closing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wordsStrings(context, 'saveError'))),
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
