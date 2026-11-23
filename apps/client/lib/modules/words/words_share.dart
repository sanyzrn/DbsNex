/// One word as text someone else can read: the word and its meaning, then
/// the example and the note if they were written, then the small line of
/// where it belongs — language, tag, deck. Plain text only, so it lands
/// intact in a chat, a message to a friend or a note in another app; no
/// picture, no link, no server.
library;

import 'words_models.dart';

String wordsShareText(WordCard card, {String deckName = ''}) {
  final headword = card.headword.trim();
  final meaning = card.meaning.trim();
  final lines = <String>[
    if (meaning.isEmpty)
      headword
    else if (headword.isEmpty)
      meaning
    else
      '$headword — $meaning',
    if (card.example.trim().isNotEmpty) card.example.trim(),
    if (card.note.trim().isNotEmpty) card.note.trim(),
  ];
  final meta = [
    if (card.language.trim().isNotEmpty) card.language.trim(),
    if (card.tag.trim().isNotEmpty) card.tag.trim(),
    if (deckName.trim().isNotEmpty) deckName.trim(),
  ];
  if (meta.isNotEmpty) lines.add(meta.join(' · '));
  return lines.where((line) => line.isNotEmpty).join('\n');
}
