import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart'
    show
        CapturedMedia,
        CapturedMediaKind,
        MediaPicker,
        NexFileKind,
        NexFileKinds,
        NexFileSignatures,
        nexDigits;
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

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

/// What a media pick produced: the files Nex can keep, and the ones it
/// refused because they are not photos or videos.
class NexMediaPick {
  const NexMediaPick({required this.media, required this.rejected});

  final List<CapturedMedia> media;
  final List<String> rejected;

  bool get isEmpty => media.isEmpty;
}

/// Opens the system media picker for photos and videos together, several at a
/// time, and keeps only what the files themselves say they are.
///
/// The picker's claim is not trusted on its own: Android's legacy document
/// picker can hand back a PDF or a ZIP for a `*/*` media request, and a cached
/// copy can arrive without a useful extension. [nexFilterMedia] reads each
/// header first, so a file that is not a photo or a video is never stored as
/// one. A refused selection is said out loud, and the File button stays the
/// separate way in for everything else.
///
/// Throws only what the platform picker throws; the caller already reports
/// those with the messages its own screen uses.
Future<NexMediaPick> nexPickMedia(
  BuildContext context, {
  required MediaPicker picker,
}) async {
  final picked = await picker.pickMedia();
  final result = await nexFilterMedia(picked);
  if (result.rejected.isNotEmpty && context.mounted) {
    nexShowMediaRejected(context, result.rejected);
  }
  return result;
}

/// Splits [picked] into the photos and videos it really holds, and the names
/// of everything else.
Future<NexMediaPick> nexFilterMedia(Iterable<CapturedMedia> picked) async {
  final media = <CapturedMedia>[];
  final rejected = <String>[];
  for (final item in picked) {
    final kind = await _realKind(item);
    if (kind == null) {
      rejected.add(
        item.name.trim().isNotEmpty ? item.name.trim() : p.basename(item.path),
      );
    } else {
      media.add(item.asKind(kind));
    }
  }
  return NexMediaPick(media: media, rejected: rejected);
}

/// Says why a picked file stayed out, naming it when there is only one.
void nexShowMediaRejected(BuildContext context, List<String> names) {
  if (names.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final persian = Localizations.localeOf(context).languageCode == 'fa';
  nexShowBanner(
    context,
    message: names.length == 1
        ? l10n.mediaSkippedOne(names.single)
        : l10n.mediaSkippedMany(nexDigits('${names.length}', persian: persian)),
    kind: NexBannerKind.failed,
  );
}

/// The kind [media] really is, from its own header.
///
/// A header that is known and is not an image or a video is a refusal, even
/// when the name says `.jpg`; that is the mislabelled file this check exists
/// for. When nothing is recognised, a specific MIME type or extension is the
/// next best account, so an unusual but genuine photo is not refused for a
/// header this reader does not know.
Future<CapturedMediaKind?> _realKind(CapturedMedia media) async {
  List<int> head;
  try {
    final handle = await File(media.path).open();
    try {
      head = await handle.read(NexFileSignatures.headLength);
    } finally {
      await handle.close();
    }
  } on FileSystemException {
    // Missing, unreadable, or gone between the pick and the check.
    return null;
  }

  final sniffed = NexFileSignatures.of(head);
  if (sniffed == NexFileKind.image) return CapturedMediaKind.image;
  if (sniffed == NexFileKind.video) return CapturedMediaKind.video;
  if (sniffed != null) return null;

  final declared = NexFileKinds.of(
    path: media.name.trim().isNotEmpty ? media.name : media.path,
    mimeType: media.mimeType,
  );
  if (declared == NexFileKind.image) return CapturedMediaKind.image;
  if (declared == NexFileKind.video) return CapturedMediaKind.video;
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
