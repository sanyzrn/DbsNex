import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'strings.dart';
import 'widgets.dart';

String chequeShareText(BuildContext context, Cheque c) => [
  c.party,
  '${chequeStrings(context, c.direction)} · ${chequeStrings(context, 'status_${c.status}')}',
  '${chequeMoney(context, c.remaining, unit: c.unit)} ${chequeStrings(context, c.unit)}',
  if (c.actionDay != null) nexModuleDateLabel(context, c.actionDay!),
].join('\n');

Future<void> shareCheque(BuildContext context, Cheque c) async {
  try {
    await nexModuleShareText(chequeShareText(context, c));
  } catch (_) {
    if (context.mounted) {
      nexShowBanner(
        context,
        message: chequeStrings(context, 'saveError'),
        kind: NexBannerKind.failed,
      );
    }
  }
}
