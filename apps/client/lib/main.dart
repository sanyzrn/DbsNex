import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_core/nex_core.dart';
import 'bootstrap_host.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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

  AIAdapterBinding.bind(const OnDeviceAIAdapter());
  runApp(const NexBootstrapHost());
}