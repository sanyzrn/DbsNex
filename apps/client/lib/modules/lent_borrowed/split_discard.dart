import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'upgrade_strings.dart';

/// Asks before a half-written split is thrown away.
///
/// Costs typed into a sheet are not a draft, so a stray swipe would take the
/// whole trip with it; leaving asks once, and only when there is something to
/// lose. Returns true when the person agreed to lose it.
Future<bool> confirmSplitDiscard(BuildContext context) async {
  final leave = await nexShowDialog<bool>(
    context: context,
    builder: (dialog) => NexAlertDialog(
      title: Text(upgradeWord(dialog, 'splitDiscardTitle')),
      content: NexDialogBody(
        child: Text(upgradeWord(dialog, 'splitDiscardBody')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: Text(AppLocalizations.of(dialog).cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialog, true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialog).colorScheme.error,
          ),
          child: Text(upgradeWord(dialog, 'splitDiscard')),
        ),
      ],
    ),
  );
  return leave == true;
}
