import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Editors using this guard must disable a modal sheet's drag dismissal,
/// which calls Navigator.pop directly and bypasses the system back check.
mixin NexDraftGuard<T extends StatefulWidget> on State<T> {
  bool get hasUnsavedChanges;
  bool _confirmingDiscard = false;

  Future<void> requestDiscard() async {
    if (_confirmingDiscard) return;
    if (!hasUnsavedChanges) {
      Navigator.of(context).pop();
      return;
    }
    _confirmingDiscard = true;
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
    _confirmingDiscard = false;
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Widget guardDraft(Widget child) => PopScope(
    canPop: !hasUnsavedChanges,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) requestDiscard();
    },
    child: child,
  );
}
