import 'dart:io';
import 'dart:isolate';

import 'package:nex_core/nex_core.dart';

import '../documents/docx_markdown.dart';

/// What Copy puts on the clipboard, with a file note's own text read in.
///
/// [Note.copyText] is synchronous and can only see the database row, and a
/// file note's row holds the file's name — so copying a Markdown or text file
/// that the details sheet shows in full put its name on the clipboard. A
/// caption still wins, as it does everywhere; without one, a text file's
/// words and a `.docx`'s text are what is copied. Anything unreadable, too
/// large or of another kind falls back to [Note.copyText].
Future<String?> nexCopyTextOf(Note note) async {
  final own = note.copyText;
  if (note.type != NoteType.file) return own;
  if (note.caption?.trim().isNotEmpty ?? false) return own;
  final path = note.mediaUri;
  if (path == null) return own;
  try {
    final file = File(path);
    if (!await file.exists()) return own;
    final size = await file.length();
    final String? text;
    if (NexFileKinds.of(path: path, mimeType: note.mimeType).isText) {
      if (size > maxCopiedFileBytes) return own;
      text = await file.readAsString();
    } else if (NexFileKinds.extensionOf(path) == 'docx') {
      if (size > NexDocx.maxBytes) return own;
      final bytes = await file.readAsBytes();
      text = (await Isolate.run(() => NexDocx.read(bytes)))?.markdown;
    } else {
      text = null;
    }
    final trimmed = text?.trim() ?? '';
    return trimmed.isEmpty ? own : trimmed;
  } catch (_) {
    // Not UTF-8, not a real .docx, gone since it was saved: the name is
    // still something to copy.
    return own;
  }
}

/// The same ceiling the details sheet renders a text file under.
const maxCopiedFileBytes = 512 * 1024;
