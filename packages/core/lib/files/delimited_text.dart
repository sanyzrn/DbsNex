/// Reads CSV and TSV into rows.
///
/// Hand-written rather than pulled in: the whole of RFC 4180 is the quoting
/// rule below, and a dependency for it would land in `packages/core`, which
/// has three and is meant to keep it that way.
///
/// Splitting on the delimiter — the obvious version — is wrong in a way that
/// is invisible until it matters: `"Tehran, Iran",2` is two fields, not three,
/// and a spreadsheet exported from anywhere real is full of them. So this is a
/// character scanner, not a `split`.
abstract final class NexDelimitedText {
  /// Parses [source] into rows of fields.
  ///
  /// [delimiter] defaults to a comma; pass `'\t'` for a `.tsv`. Handles quoted
  /// fields, `""` as an escaped quote inside one, newlines inside quotes, and
  /// CRLF or LF line endings. A trailing newline does not produce an empty
  /// final row.
  ///
  /// Rows are returned exactly as long as the file wrote them — ragged input
  /// stays ragged, because padding it would be inventing cells. Whoever draws
  /// a table decides what to do about that.
  static List<List<String>> parse(String source, {String delimiter = ','}) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (quoted) {
        if (char != '"') {
          field.write(char);
          continue;
        }
        // A doubled quote inside a quoted field is one literal quote; a lone
        // one closes the field.
        if (i + 1 < source.length && source[i + 1] == '"') {
          field.write('"');
          i++;
          continue;
        }
        quoted = false;
        continue;
      }
      if (char == '"' && field.isEmpty) {
        quoted = true;
        continue;
      }
      if (char == delimiter) {
        endField();
        continue;
      }
      if (char == '\n') {
        endRow();
        continue;
      }
      // Bare CR before an LF is a line ending; anywhere else it is content.
      if (char == '\r') {
        if (i + 1 < source.length && source[i + 1] == '\n') continue;
        endRow();
        continue;
      }
      field.write(char);
    }
    // Whatever is still in hand is the last row — unless the file ended on its
    // line break, in which case there is nothing left to flush.
    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  /// The delimiter a file with this extension uses.
  static String delimiterFor(String extension) =>
      extension.toLowerCase() == 'tsv' ? '\t' : ',';
}
