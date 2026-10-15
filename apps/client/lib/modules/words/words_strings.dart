import 'package:nex_client/modules/module_api.dart';

import 'words_strings_en.dart';
import 'words_strings_fa.dart';

/// Every word Word by Word shows, held together in both languages — the
/// module kit's test holds the two sides to the same keys.
///
/// Numbers never sit inside these sentences; they arrive as `{placeholder}`
/// arguments. Numeric arguments come out in Persian digits on the Persian
/// side, through the strings' own behaviour.
const NexModuleStrings wordsStrings = NexModuleStrings(
  en: wordsStringsEn,
  fa: wordsStringsFa,
);
