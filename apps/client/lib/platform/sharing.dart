import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:nex_core/nex_core.dart';
import 'package:share_plus/share_plus.dart';

/// Whether this platform has a share sheet worth offering.
///
/// share_plus compiles for Windows and does something there, but what it does
/// is not a share sheet a person recognises, and on a real machine it did not
/// work at all. An action that is present and does nothing is worse than an
/// action that is absent: the first teaches you the app is broken, the second
/// teaches you the platform does not do that.
///
/// Windows has an answer to "get this file out of the app", and it is not
/// sharing — it is Save As. See [nexSendFileOut].
bool get nexCanShare =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

/// What happened to a file the user asked to get out of the app.
enum SendOutcome {
  /// Handed to the share sheet.
  shared,

  /// Written to a location the user chose.
  saved,

  /// The user backed out of the picker. Not a failure.
  cancelled,
}

/// Gets a file out of the app by whichever route the platform actually has.
///
/// The export used to go straight to the share sheet, which is right on a
/// phone — a zip sitting in the app's cache is not a backup anyone can keep —
/// and on Windows meant the export silently went nowhere reachable. A save
/// dialog is the same intent expressed in the idiom of the platform.
Future<SendOutcome> nexSendFileOut(
  String path, {
  String? suggestedName,
  String? mimeType,
}) async {
  final name = suggestedName ?? path.split(Platform.pathSeparator).last;

  if (nexCanShare) {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType)],
        fileNameOverrides: [name],
      ),
    );
    return SendOutcome.shared;
  }

  final location = await getSaveLocation(suggestedName: name);
  if (location == null) return SendOutcome.cancelled;
  await File(path).copy(location.path);
  return SendOutcome.saved;
}

/// Hands one note to the platform's share sheet.
///
/// Its media where it has some — a photo shared as a photo is what anyone
/// expects — and its words otherwise. Returns false when there was nothing to
/// send, so the caller can say so rather than opening an empty share sheet.
///
/// Here rather than in the detail sheet because a swipe on the timeline can be
/// bound to the same thing, and a second copy would be a second answer to
/// "what does sharing a voice note actually send".
Future<bool> nexShareNote(Note note) async {
  final uri = note.mediaUri;
  if (uri != null && File(uri).existsSync()) {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(uri, mimeType: note.mimeType)],
        text: note.caption?.trim().isNotEmpty == true ? note.caption : null,
      ),
    );
    return true;
  }
  final text = note.displayText?.trim() ?? '';
  if (text.isEmpty) return false;
  await SharePlus.instance.share(ShareParams(text: text));
  return true;
}
