import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_screen.dart';
import 'words_strings.dart';

/// «Word by Word» — an offline vocabulary box: capture the words you meet
/// with your own meanings, review them on a small deterministic ladder of
/// days, keep the history on this phone.
class WordsModule extends NexStoredModule {
  const WordsModule();

  @override
  String get id => 'words';

  @override
  IconData get icon => Icons.translate_outlined;

  @override
  NexHue get hue => NexHue.violet;

  @override
  NexModuleStrings get strings => wordsStrings;

  @override
  Widget screen(NexModuleStore store) => WordsScreen(store: store);
}
