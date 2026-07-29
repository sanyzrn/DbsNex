import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands a file to whatever the operating system uses to open it.
///
/// `open_filex` is the obvious tool and it declares exactly two platforms in
/// its pubspec — `android` and `ios`. On Windows there is no implementation at
/// all, so every call went to the platform channel and came back as a
/// `MissingPluginException`. That broke two things on a shipped desktop target:
/// opening a note's media, and — worse — launching the downloaded update, so
/// the whole in-app updater fetched an installer it could never run.
///
/// Desktop goes through `url_launcher`, whose Windows implementation is
/// `ShellExecute`. That is also the correct way to start an installer rather
/// than a bare `Process.start`: ShellExecute is what raises the UAC prompt.
enum FileOpenOutcome {
  opened,

  /// The OS refused, or nothing is registered for this kind of file. On
  /// Android this is usually the "install unknown apps" permission.
  failed,
}

/// Which mechanism a platform uses. Split out so the routing is testable
/// without a plugin: the bug was a platform the code never considered, and a
/// test that cannot ask "what would Windows do" cannot catch the next one.
@visibleForTesting
enum FileOpenStrategy { plugin, shell }

@visibleForTesting
FileOpenStrategy strategyFor({
  required bool isAndroid,
  required bool isIOS,
}) =>
    isAndroid || isIOS ? FileOpenStrategy.plugin : FileOpenStrategy.shell;

Future<FileOpenOutcome> nexOpenFile(String path, {String? mimeType}) async {
  final strategy = strategyFor(
    isAndroid: Platform.isAndroid,
    isIOS: Platform.isIOS,
  );

  switch (strategy) {
    case FileOpenStrategy.plugin:
      final result = await OpenFilex.open(path, type: mimeType);
      return result.type == ResultType.done
          ? FileOpenOutcome.opened
          : FileOpenOutcome.failed;

    case FileOpenStrategy.shell:
      try {
        final opened = await launchUrl(Uri.file(path));
        return opened ? FileOpenOutcome.opened : FileOpenOutcome.failed;
      } catch (_) {
        // A path the shell cannot represent, or no handler at all. Either way
        // the caller's job is to say so, not to crash.
        return FileOpenOutcome.failed;
      }
  }
}
