import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'nex_dialog.dart';
import 'keyboard_dismisser.dart';

/// Editors using this guard must disable a modal sheet's drag dismissal,
/// which calls Navigator.pop directly and bypasses the system back check.
mixin NexDraftGuard<T extends StatefulWidget> on State<T> {
  bool get hasUnsavedChanges;
  bool _confirmingDiscard = false;
  void discardDraft() {}

  Future<void> requestDiscard() async {
    if (_confirmingDiscard) return;
    _confirmingDiscard = true;
    if (!hasUnsavedChanges) {
      discardDraft();
      nexDismissKeyboard(context);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final l10n = AppLocalizations.of(context);
    final discard = await nexShowDialog<bool>(
      context: context,
      builder: (ctx) => NexAlertDialog(
        title: Text(l10n.unsavedChanges),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.discard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.keepEditing),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      discardDraft();
      nexDismissKeyboard(context);
      if (mounted) Navigator.of(context).pop();
    } else {
      _confirmingDiscard = false;
    }
  }

  Widget guardDraft(Widget child) => PopScope(
    canPop: !hasUnsavedChanges,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) requestDiscard();
    },
    child: child,
  );
}
