/// Text as search compares it: one spelling for the letters and digits that
/// Persian is written with in more than one way (ADR-028).
///
/// The same word reaches the library in several codepoint spellings. Arabic
/// yeh and kaf (ي ك) arrive from Windows-1256 text files — that code page has
/// no Persian yeh — from cloud OCR and from pasted Arabic-script text, while a
/// Persian keyboard types ی and ک. Harakat and tatweel decorate a word without
/// changing it. A ZWNJ is typed by some people and not others («کتاب‌ها»,
/// «کتابها»). Digits come as Latin, Persian or Arabic-Indic. To the FTS5
/// tokenizer each of these was a different word, so a note was found only when
/// the query happened to be spelled the way the note was.
///
/// This is the query side, and the word inside [nexSearchIndexText]. It is
/// never applied to what is shown: the note keeps the letters it was written
/// with.
String nexSearchFold(String text) => text.replaceAllMapped(
  _searchFoldChanges,
  (match) => switch (match[0]!.codeUnitAt(0)) {
    // Yeh with hamza (ئ) and alef with madda (آ) remain distinct.
    0x064A || 0x0649 => 'ی',
    0x0643 => 'ک',
    0x06C0 || 0x0629 => 'ه',
    0x0623 || 0x0625 || 0x0671 => 'ا',
    0x0624 => 'و',
    final digit && >= 0x06F0 && <= 0x06F9 => String.fromCharCode(
      0x30 + digit - 0x06F0,
    ),
    final digit && >= 0x0660 && <= 0x0669 => String.fromCharCode(
      0x30 + digit - 0x0660,
    ),
    // The other matched code points are harakat, tatweel and joiners.
    _ => '',
  },
);

// Match only code points that need folding, so large blocks of plain text
// can be copied together and text that needs no folding is returned as-is.
final _searchFoldChanges = RegExp(
  r'[\u0623-\u0625\u0629\u0640\u0643\u0649-\u064a'
  r'\u064b-\u065f\u0660-\u0669\u0670-\u0671\u06c0'
  r'\u06f0-\u06f9\u200c-\u200f]',
);

/// What the search index holds for [text]: [nexSearchFold]ed, with each word
/// that has a ZWNJ in it present twice, split and joined.
///
/// The split form («کتاب ها») is what an exact query word matches — «کتاب»
/// finds «کتاب‌ها», as it always has. The joined form («کتابها») is what a
/// query typed without the ZWNJ matches, since [nexSearchFold] takes the ZWNJ
/// out of the query: «کتابها» finds «کتاب‌ها» too. One spelling of the index
/// could serve only one of the two.
String nexSearchIndexText(String text) {
  const zwnj = '\u200C';
  final split = nexSearchFold(text.replaceAll(zwnj, ' '));
  if (!text.contains(zwnj)) return split;
  final joined = <String>{
    for (final word in text.split(RegExp(r'\s+')))
      if (word.contains(zwnj)) nexSearchFold(word),
  };
  return '$split\n${joined.join(' ')}';
}

/// The words a query actually has to look for: [nexSearchFold]ed, with the
/// two characters FTS5 reads as syntax — the quote and the star — taken out
/// rather than escaped, and split on whitespace.
///
/// One definition for every place that asks "does this query say anything?".
/// It used to be re-derived in each, and the one in the substring pass had no
/// answer at all: a query of only quotes, or only the half-space a Persian
/// keyboard makes with Shift+Space, folds to nothing there, and
/// `instr(content, '')` is true of every row — one stray keystroke listed the
/// whole library as a match for it. An empty list is the honest answer: no
/// words, nothing to find.
List<String> nexSearchTokens(String text) => [
  for (final token in nexSearchFold(
    text,
  ).replaceAll('"', ' ').replaceAll('*', ' ').split(RegExp(r'\s+')))
    if (token.isNotEmpty) token,
];
