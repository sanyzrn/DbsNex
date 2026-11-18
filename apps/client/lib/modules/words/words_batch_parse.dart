/// Reading a pasted list: one word per line, its meaning after a
/// separator if there is one. A Tab has always worked; a dash, a colon or
/// an equal sign works too, because that is how a list arrives from a
/// notebook, a spreadsheet or a chat.
///
/// Nothing is saved here — this only says what the lines mean, so the
/// person can look at the preview before anything is added.
library;

import 'words_models.dart';

class WordsBatchLine {
  const WordsBatchLine(this.word, this.meaning);
  final String word;
  final String meaning;
}

/// The separators a line may use, in the order they are looked for at the
/// same position. A plain hyphen is not one of them: «well-being» is a
/// word, not a word and a meaning. Spaced hyphens, en dashes and em
/// dashes are.
const List<String> _separators = [
  '\t',
  ' = ',
  '=',
  ' - ',
  ' – ',
  ' — ',
  '–',
  '—',
  ': ',
  '：',
];

/// Where the word ends on [line], or -1 when the line is only a word.
int _separatorAt(String line) {
  for (var index = 0; index < line.length; index++) {
    for (final separator in _separators) {
      if (!line.startsWith(separator, index)) continue;
      // A colon only splits when a space follows it (or it is full-width):
      // «http://…» and «10:30» are one piece of text.
      if (separator == ': ' || separator == '：') {
        return index;
      }
      return index;
    }
  }
  return -1;
}

({List<WordsBatchLine> entries, int duplicates}) parseWordsBatch(String text) {
  final seen = <String>{};
  final entries = <WordsBatchLine>[];
  var duplicates = 0;
  for (final raw in text.split('\n')) {
    final at = _separatorAt(raw);
    final word = foldWhitespace(at < 0 ? raw : raw.substring(0, at));
    if (word.isEmpty) continue;
    if (!seen.add(word.toLowerCase())) {
      duplicates++;
      continue;
    }
    final meaning = at < 0
        ? ''
        : raw
              .substring(at + _separatorLength(raw, at))
              .replaceFirst(RegExp(r'^[ \t]+'), '')
              .trim();
    entries.add(WordsBatchLine(word, meaning));
  }
  return (entries: entries, duplicates: duplicates);
}

/// The separator actually found at [at] on [line] — the first one in the
/// list wins, so a Tab stays a Tab and an equals sign is not read as the
/// start of a longer one.
int _separatorLength(String line, int at) {
  for (final separator in _separators) {
    if (line.startsWith(separator, at)) return separator.length;
  }
  return 1;
}
