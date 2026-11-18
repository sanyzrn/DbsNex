/// Decks: the collections a person sorts their words into — a book, a
/// course, a trip. A word may sit outside every deck, and nothing is lost
/// when a deck goes: its words stay, only the grouping does.
///
/// Kind `deck`, one record per deck:
/// `{"schema":1,"name":"The Little Prince","createdAt":"2026-11-17T09:00:00"}`.
/// A card names its deck in `deckId`; an empty id means no deck.
library;

import 'words_models.dart';

const String wordsDeckKind = 'deck';

class WordsDeck {
  const WordsDeck({
    required this.id,
    required this.name,
    this.createdAtIso = '',
  });

  final String id;
  final String name;
  final String createdAtIso;

  factory WordsDeck.fromRecord(String id, Map<String, Object?> body) =>
      WordsDeck(
        id: id,
        name: foldWhitespace('${body['name'] ?? ''}'),
        createdAtIso: '${body['createdAt'] ?? ''}',
      );

  Map<String, Object?> toRecord() => {
    'schema': 1,
    'name': name,
    'createdAt': createdAtIso,
  };

  WordsDeck copyWith({String? name}) =>
      WordsDeck(id: id, name: name ?? this.name, createdAtIso: createdAtIso);
}

/// The decks in the person's own order: by name, folded so case does not
/// split two spellings of one book.
List<WordsDeck> sortDecks(Iterable<WordsDeck> decks) {
  final kept = decks.where((deck) => deck.name.isNotEmpty).toList();
  kept.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return kept;
}

/// The name of the deck [id] names, or null when the deck is gone.
String? wordsDeckName(List<WordsDeck> decks, String id) {
  if (id.isEmpty) return null;
  for (final deck in decks) {
    if (deck.id == id) return deck.name;
  }
  return null;
}

/// The deck [card] sits in, as the screens see it: its `deckId` when that
/// deck exists, and «no deck» when it is empty or names a deck that has
/// gone (removed on another phone, or named by an older draft) — such a
/// word must never fall out of every deck filter.
String wordsCardDeck(List<WordsDeck> decks, WordCard card) =>
    wordsDeckName(decks, card.deckId) == null ? '' : card.deckId;

/// How many of [cards] sit in the deck [id] — the «words without a deck»
/// chip counts an empty id the same way.
int wordsInDeck(Iterable<WordCard> cards, String id) =>
    cards.where((card) => card.deckId == id).length;
