import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform/crash_reporter.dart';

/// The setup every Dart entry point (`main.dart`, `main_ai.dart` — ADR-031)
/// needs before binding its adapters and calling `runApp`. Factored out so
/// the two entry points differ only by which adapters they bind, not by
/// re-declaring this sequence.
Future<void> bootstrapEntry() async {
  WidgetsFlutterBinding.ensureInitialized();

  // As early as this can happen: an error during bootstrap is exactly the
  // kind this exists to catch. Local file only — see NexCrashLog's own doc
  // comment for why nothing here is a telemetry SDK in disguise.
  (await NexCrashLog.open()).install();

  // The app targets SDK 35, where Android draws edge to edge whether or not the
  // app asked. Declaring it is what makes the platform report the real inset
  // sizes, so a three-button navigation bar becomes padding the layout can
  // respect instead of a strip the content silently runs underneath.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      // Deprecated on 15 and ignored there, but this build still runs on
      // older releases, where a contrast scrim would sit over the bar.
      systemNavigationBarContrastEnforced: false,
    ),
  );
}
