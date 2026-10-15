/// Every word Gold Check shows, held together in both languages — the
/// module kit's test holds the two sides to the same keys.
///
/// Numbers never sit inside these sentences; they arrive as `{placeholder}`
/// arguments the caller has already formatted (Persian digits on the
/// Persian side) through `gold_format.dart`.
library;

import 'package:nex_client/modules/module_api.dart';

import 'gold_strings_en.dart';
import 'gold_strings_fa.dart';

const NexModuleStrings goldStrings = NexModuleStrings(
  en: goldStringsEn,
  fa: goldStringsFa,
);
