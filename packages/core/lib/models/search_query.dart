import 'note.dart';

/// A typed search string, split into what it filters by and what it looks for.
///
/// `tag:work type:link cooler` is three different questions in one line: only
/// notes tagged work, only links, and the word "cooler" somewhere in them. The
/// filter row can express the first two by tapping, and this is the same thing
/// for people who would rather type it — and the only way to express them at
/// all in a saved search, which is a string and nothing more.
class SearchQuery {
  const SearchQuery({
    this.text = '',
    this.tagNames = const [],
    this.types = const [],
  });

  /// What is left after the operators are taken out — what actually goes to
  /// full-text search.
  final String text;

  /// Tag *names*, not ids. Someone typing a search knows the word they wrote
  /// on the tag; ids are resolved against the library by the caller, which is
  /// also what lets an unknown name mean "no results" rather than "ignored".
  final List<String> tagNames;

  final List<NoteType> types;

  bool get hasFilters => tagNames.isNotEmpty || types.isNotEmpty;
}

/// Operators, and everything else as search terms.
///
/// Deliberately forgiving. `tag:` with nothing after it, an unknown type, a
/// stray colon inside a word — all of these are ordinary text in a notes app,
/// and a parser that rejected them would turn a search box into a syntax
/// exam. The rule is: a token is an operator only when it is spelled exactly
/// right and carries a value; otherwise it is something the user is looking
/// for.
SearchQuery parseSearchQuery(String raw) {
  final tags = <String>[];
  final types = <NoteType>[];
  final terms = <String>[];

  for (final token in _tokenise(raw)) {
    final colon = token.indexOf(':');
    if (colon <= 0 || colon == token.length - 1) {
      terms.add(token);
      continue;
    }
    final operator = token.substring(0, colon).toLowerCase();
    final value = token.substring(colon + 1);
    switch (operator) {
      case 'tag':
        tags.add(value);
      case 'type':
        final type = _typeNamed(value);
        if (type == null) {
          terms.add(token);
        } else {
          types.add(type);
        }
      default:
        terms.add(token);
    }
  }

  return SearchQuery(
    text: terms.join(' '),
    tagNames: List.unmodifiable(tags),
    types: List.unmodifiable(types),
  );
}

/// Splits on whitespace, keeping quoted runs together.
///
/// `tag:"to read"` and `"the cooler"` both have to survive, because a tag with
/// a space in it is ordinary and a phrase search is the first thing anyone
/// tries.
List<String> _tokenise(String raw) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (final rune in raw.runes) {
    final char = String.fromCharCode(rune);
    if (char == '"') {
      quoted = !quoted;
      continue;
    }
    if (!quoted && char.trim().isEmpty) {
      if (buffer.isNotEmpty) tokens.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) tokens.add(buffer.toString());
  return tokens;
}

NoteType? _typeNamed(String value) {
  final wanted = value.toLowerCase();
  for (final type in NoteType.values) {
    if (type.wireName == wanted) return type;
  }
  // The plurals people actually type.
  return switch (wanted) {
    'notes' || 'note' => NoteType.text,
    'photos' || 'image' || 'images' => NoteType.photo,
    'voices' || 'audio' => NoteType.voice,
    'files' => NoteType.file,
    'checklists' || 'todo' || 'todos' => NoteType.checklist,
    'links' || 'url' => NoteType.link,
    _ => null,
  };
}
