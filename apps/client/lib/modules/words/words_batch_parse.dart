import 'words_models.dart';

class WordsBatchLine {
  const WordsBatchLine(this.word, this.meaning);
  final String word;
  final String meaning;
}

({List<WordsBatchLine> entries, int duplicates}) parseWordsBatch(String text) {
  final seen = <String>{};
  final entries = <WordsBatchLine>[];
  var duplicates = 0;
  for (final raw in text.split('\n')) {
    final tab = raw.indexOf('\t');
    final word = foldWhitespace(tab < 0 ? raw : raw.substring(0, tab));
    if (word.isEmpty) continue;
    if (!seen.add(word.toLowerCase())) {
      duplicates++;
      continue;
    }
    final meaning = tab < 0 ? '' : raw.substring(tab + 1).trim();
    entries.add(WordsBatchLine(word, meaning));
  }
  return (entries: entries, duplicates: duplicates);
}
