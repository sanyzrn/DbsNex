/// File names a person sees, chooses or saves under.
///
/// Shared by "Rename" on a file note, "Save to device" and the Markdown file a
/// text note becomes, so all three agree on what a valid name is.
library;

/// Characters no common file system accepts in a name (Windows is the
/// strictest), plus control characters.
final _forbidden = RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]');

/// The longest name kept, extension included. Long enough for any real
/// title, short enough for every file system and share target.
const nexMaxFileNameLength = 120;

/// The extension of [name] with its dot (`.pdf`), or `''` when it has none.
/// A leading dot alone (`.env`) is a name, not an extension.
String fileExtensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  final ext = name.substring(dot);
  return ext.length <= 10 && !ext.contains(' ') ? ext : '';
}

/// [name] without its extension.
String fileBaseNameOf(String name) {
  final ext = fileExtensionOf(name);
  return ext.isEmpty ? name : name.substring(0, name.length - ext.length);
}

/// [raw] made safe to use as a file name: forbidden characters become a
/// space, runs of spaces collapse, leading and trailing dots and spaces go,
/// and the result is cut to [nexMaxFileNameLength] keeping [extension].
/// Null when nothing usable is left.
String? safeFileName(String raw, {String extension = ''}) {
  var base = raw
      .replaceAll(_forbidden, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s.]+|[\s.]+$'), '');
  if (base.isEmpty) return null;
  final room = nexMaxFileNameLength - extension.length;
  if (base.length > room) base = base.substring(0, room).trimRight();
  return '$base$extension';
}

/// Why a name typed into "Rename" was refused, or null when it is fine.
enum FileNameProblem { empty, forbiddenCharacters, tooLong }

/// Checks a base name typed by the person (no extension), before anything
/// is changed: a name with forbidden characters is refused with a reason
/// rather than quietly rewritten, because the person is looking at it.
FileNameProblem? checkFileBaseName(String base, {String extension = ''}) {
  final trimmed = base.trim();
  if (trimmed.isEmpty || RegExp(r'^\.+$').hasMatch(trimmed)) {
    return FileNameProblem.empty;
  }
  if (_forbidden.hasMatch(trimmed)) return FileNameProblem.forbiddenCharacters;
  if (trimmed.length + extension.length > nexMaxFileNameLength) {
    return FileNameProblem.tooLong;
  }
  return null;
}

/// The name a text note's Markdown file gets: its first line, made safe,
/// with `.md`; or `note.md` when the note has no usable first line.
String markdownFileNameFor(String text) {
  final firstLine = text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'^[#>\-*\s]+'), '').trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  final short = firstLine.length > 60
      ? firstLine.substring(0, 60).trimRight()
      : firstLine;
  return safeFileName(short, extension: '.md') ?? 'note.md';
}
