import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

/// What "Save to device" did.
enum SaveOutcome {
  /// A copy was written where the person chose.
  saved,

  /// The person backed out of the save dialog. Not a failure.
  cancelled,

  /// The copy could not be written.
  failed,
}

/// What a note is saved as: an existing file at [sourcePath], or [text]
/// written to a new one, under [name].
typedef NoteSaveTarget = ({
  String name,
  String mimeType,
  String? sourcePath,
  String? text,
});

/// Decides what [note] is saved as, or null when it has nothing to save.
///
/// A note with a file saves that file: a file note under its own name, a
/// photo or recording under its caption or the moment it was taken. A note
/// of words saves as Markdown, named after its first line, which is what
/// "Convert to Markdown" would have made of it.
NoteSaveTarget? nexSaveTargetFor(Note note) {
  final uri = note.mediaUri;
  if (uri != null && uri.isNotEmpty) {
    final ext = fileExtensionOf(uri.split(Platform.pathSeparator).last);
    final mime = note.mimeType ?? _mimeFor(ext);
    if (note.type == NoteType.file) {
      final own = note.originalFilename?.trim() ?? '';
      final ownExt = fileExtensionOf(own);
      final name =
          safeFileName(
            fileBaseNameOf(own),
            extension: ownExt.isEmpty ? ext : ownExt,
          ) ??
          'Nex file$ext';
      return (name: name, mimeType: mime, sourcePath: uri, text: null);
    }
    final kind = note.type == NoteType.voice ? 'voice' : 'photo';
    final caption = note.caption?.trim() ?? '';
    final name =
        safeFileName(caption, extension: ext) ??
        'Nex $kind ${_stamp(note.createdAt)}$ext';
    return (name: name, mimeType: mime, sourcePath: uri, text: null);
  }
  final text = _markdownOf(note);
  if (text == null) return null;
  return (
    name: markdownFileNameFor(
      note.title?.trim().isNotEmpty == true ? note.title! : text,
    ),
    mimeType: 'text/markdown',
    sourcePath: null,
    text: text,
  );
}

String? _markdownOf(Note note) {
  switch (note.type) {
    case NoteType.link:
      final url = note.linkUrl;
      if (url == null || url.isEmpty) return null;
      final title = note.title?.trim();
      final caption = note.caption?.trim();
      return [
        title == null || title.isEmpty ? '<$url>' : '[$title]($url)',
        if (caption != null && caption.isNotEmpty) caption,
        if (note.linkExcerpt?.trim().isNotEmpty == true)
          note.linkExcerpt!.trim(),
      ].join('\n\n');
    case NoteType.text:
    case NoteType.checklist:
      final body = note.content?.trim() ?? '';
      return body.isEmpty ? null : '$body\n';
    case NoteType.voice:
    case NoteType.photo:
    case NoteType.file:
      final words = note.displayText?.trim() ?? '';
      return words.isEmpty ? null : '$words\n';
  }
}

String _stamp(DateTime at) {
  final t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}${two(t.minute)}';
}

String _mimeFor(String ext) => switch (ext.toLowerCase()) {
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.png' => 'image/png',
  '.webp' => 'image/webp',
  '.m4a' => 'audio/mp4',
  '.aac' => 'audio/aac',
  '.wav' => 'audio/wav',
  '.ogg' => 'audio/ogg',
  '.mp3' => 'audio/mpeg',
  '.pdf' => 'application/pdf',
  '.md' => 'text/markdown',
  '.txt' => 'text/plain',
  _ => 'application/octet-stream',
};

const _osChannel = MethodChannel('nex/os_capture');

/// Saves a copy of [note] where the person chooses: the system's own save
/// dialog on Android, Save As on the desktop. Null when the note has nothing
/// to save. A photo goes without where and when it was taken, as it does
/// when shared (SEC-08).
Future<SaveOutcome?> nexSaveNoteToDevice(Note note) async {
  final target = nexSaveTargetFor(note);
  if (target == null) return null;
  final staged = <Directory>[];
  try {
    String path;
    if (target.sourcePath != null) {
      if (!File(target.sourcePath!).existsSync()) return SaveOutcome.failed;
      path = (await _shareable(note, target.sourcePath!, staged)).path;
    } else {
      final folder = await Directory.systemTemp.createTemp('nex-save-');
      staged.add(folder);
      final file = File(
        '${folder.path}${Platform.pathSeparator}${target.name}',
      );
      await file.writeAsString(target.text!, flush: true);
      path = file.path;
    }
    return await nexSaveFileToDevice(
      path,
      name: target.name,
      mimeType: target.mimeType,
    );
  } catch (_) {
    return SaveOutcome.failed;
  } finally {
    _cleanUp(staged);
  }
}

/// Saves a copy of the file at [path] under [name] where the person chooses.
Future<SaveOutcome> nexSaveFileToDevice(
  String path, {
  required String name,
  String mimeType = 'application/octet-stream',
  @visibleForTesting bool? android,
}) async {
  if (android ?? (!kIsWeb && Platform.isAndroid)) {
    try {
      final answer = await _osChannel.invokeMethod<String>('saveToDevice', {
        'path': path,
        'name': name,
        'mimeType': mimeType,
      });
      return switch (answer) {
        'saved' => SaveOutcome.saved,
        'cancelled' => SaveOutcome.cancelled,
        _ => SaveOutcome.failed,
      };
    } on PlatformException {
      return SaveOutcome.failed;
    } on MissingPluginException {
      return SaveOutcome.failed;
    }
  }
  if (!kIsWeb && Platform.isIOS) {
    // iOS has no save dialog an app can open; "Save to Files" lives in the
    // share sheet.
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType)],
        fileNameOverrides: [name],
      ),
    );
    return SaveOutcome.saved;
  }
  final location = await getSaveLocation(suggestedName: name);
  if (location == null) return SaveOutcome.cancelled;
  await File(path).copy(location.path);
  return SaveOutcome.saved;
}
