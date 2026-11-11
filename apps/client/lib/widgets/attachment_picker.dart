import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/os_capture_bridge.dart';
import 'nex_banner.dart';

/// Cancellation is quiet; refusals explain why the file was not imported.
Future<PickedOsFile?> nexPickAttachment(
  BuildContext context, {
  Future<PickedOsFile?> Function()? pickFile,
}) async {
  try {
    return await (pickFile ?? OsCaptureBridge.pickFile)();
  } on AttachmentSizeException catch (error) {
    if (context.mounted) nexShowAttachmentTooLarge(context, error.rejection);
  } catch (_) {
    if (context.mounted) {
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).attachFailed,
        kind: NexBannerKind.failed,
      );
    }
  }
  return null;
}

void nexShowAttachmentTooLarge(BuildContext context, RejectedShare rejection) {
  final persian = Localizations.localeOf(context).languageCode == 'fa';
  nexShowBanner(
    context,
    message: AppLocalizations.of(context).shareTooLarge(
      rejection.filename,
      nexDigits(nexFormatBytes(rejection.bytes), persian: persian),
      nexDigits(nexFormatBytes(rejection.limit), persian: persian),
    ),
    kind: NexBannerKind.failed,
  );
}
