import 'package:flutter/material.dart';

import 'app.dart';
import 'platform/nex_preferences.dart';
import 'platform/nex_services.dart';
import 'platform/os_capture_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await NexPreferences.load();
  final services = await NexServices.bootstrap(preferences: preferences);
  services.applyAiPreferences(preferences);
  final osCapture = OsCaptureBridge(services);
  await osCapture.start();
  runApp(
    NexApp(
      services: services,
      preferences: preferences,
      osCapture: osCapture,
    ),
  );
}
