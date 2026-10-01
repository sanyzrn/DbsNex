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
String nexSearchFold(String text) {
  if (text.isEmpty) return text;
  final out = StringBuffer();
  for (final unit in text.runes) {
    switch (unit) {
      // Yeh: Arabic yeh and alef maksura. Yeh with hamza (ئ) is a letter of
      // its own, as in «مسئله», and is left alone.
      case 0x064A || 0x0649:
        out.writeCharCode(0x06CC);
      // Kaf: Arabic kaf.
      case 0x0643:
        out.writeCharCode(0x06A9);
      // Heh with yeh above and teh marbuta read as heh.
      case 0x06C0 || 0x0629:
        out.writeCharCode(0x0647);
      // Alef with hamza above or below, and alef wasla. Alef madda (آ) is a
      // letter of its own in Persian and is left alone.
      case 0x0623 || 0x0625 || 0x0671:
        out.writeCharCode(0x0627);
      // Waw with hamza.
      case 0x0624:
        out.writeCharCode(0x0648);
      // Harakat, the superscript alef, tatweel, and the joiners and marks
      // that carry no letter: ZWNJ, ZWJ, LRM, RLM.
      case >= 0x064B && <= 0x065F:
      case 0x0670 || 0x0640:
      case 0x200C || 0x200D || 0x200E || 0x200F:
        break;
      // Persian and Arabic-Indic digits, as Latin ones.
      case >= 0x06F0 && <= 0x06F9:
        out.writeCharCode(0x30 + unit - 0x06F0);
      case >= 0x0660 && <= 0x0669:
        out.writeCharCode(0x30 + unit - 0x0660);
      default:
        out.writeCharCode(unit);
    }
  }
  return out.toString();
}

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
