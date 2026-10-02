import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:nex_core/nex_core.dart';
import 'package:share_plus/share_plus.dart';

import 'photo_metadata.dart';

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
    final staged = <Directory>[];
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [await _shareable(note, uri, staged)],
          text: note.caption?.trim().isNotEmpty == true ? note.caption : null,
        ),
      );
    } finally {
      _cleanUp(staged);
    }
    return true;
  }
  final text = note.displayText?.trim() ?? '';
  if (text.isEmpty) return false;
  await SharePlus.instance.share(ShareParams(text: text));
  return true;
}

/// Hands several notes to the share sheet at once, from the selection bar.
///
/// One note is exactly [nexShareNote]. Several go as one share: every file
/// the notes carry, and the words of the ones that are only words, a blank
/// line between each, in the order they were picked. Returns false when
/// none of them had anything to send.
Future<bool> nexShareNotes(List<Note> notes) async {
  if (notes.length == 1) return nexShareNote(notes.single);
  final files = <XFile>[];
  final words = <String>[];
  final staged = <Directory>[];
  for (final note in notes) {
    final uri = note.mediaUri;
    if (uri != null && File(uri).existsSync()) {
      files.add(await _shareable(note, uri, staged));
      final caption = note.caption?.trim() ?? '';
      if (caption.isNotEmpty) words.add(caption);
      continue;
    }
    final text = note.displayText?.trim() ?? '';
    if (text.isNotEmpty) words.add(text);
  }
  if (files.isEmpty && words.isEmpty) return false;
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: files.isEmpty ? null : files,
        text: words.isEmpty ? null : words.join('\n\n'),
      ),
    );
  } finally {
    _cleanUp(staged);
  }
  return true;
}

/// The file to hand to the share sheet for [note]'s media at [path].
///
/// A photo goes out without where and when it was taken (SEC-08): a copy
/// with its metadata stripped, staged in a temporary folder that is added to
/// [staged] for the caller to remove. Everything else, and a photo that is
/// not a JPEG or cannot be read, goes out as it is stored.
Future<XFile> _shareable(Note note, String path, List<Directory> staged) async {
  final original = XFile(path, mimeType: note.mimeType);
  if (note.type != NoteType.photo) return original;
  try {
    final bytes = await File(path).readAsBytes();
    final clean = jpegWithoutMetadata(bytes);
    if (identical(clean, bytes)) return original;
    final folder = await Directory.systemTemp.createTemp('nex-share-');
    staged.add(folder);
    final copy = File(
      '${folder.path}${Platform.pathSeparator}'
      '${path.split(Platform.pathSeparator).last}',
    );
    await copy.writeAsBytes(clean, flush: true);
    return XFile(copy.path, mimeType: note.mimeType);
  } catch (_) {
    return original;
  }
}

void _cleanUp(List<Directory> staged) {
  for (final folder in staged) {
    try {
      folder.deleteSync(recursive: true);
    } catch (_) {
      // The system clears its temporary folder on its own.
    }
  }
}
