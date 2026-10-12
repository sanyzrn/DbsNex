/// Everything a module may use, in one import — see `docs/18-module-kit.md`.
///
/// A module's files import this, Flutter, `dart:async`, `dart:math`,
/// `dart:convert`, `dart:collection` and each other, and nothing else; the
/// module kit's test (`test/module_kit_test.dart`) fails the build on any
/// other import. That is what lets a module written elsewhere be dropped in
/// without being able to reach the notes, the network, the file system or
/// the rest of the app.
library;

export 'package:nex_data/nex_data.dart' show ModuleRecord;
export 'package:nex_ui/nex_ui.dart';

export '../l10n/app_localizations.dart' show AppLocalizations;
export '../widgets/nex_dialog.dart' show nexShowSheet, NexDialogBody;
export '../widgets/nex_shelf.dart';
export 'nex_module_store.dart';
export 'nex_module_strings.dart';
export 'nex_stored_module.dart';
