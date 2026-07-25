import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import 'platform/nex_services.dart';
import 'screens/timeline_screen.dart';

/// Nex application shell (Phase 1).
class NexApp extends StatelessWidget {
  const NexApp({super.key, required this.services});

  final NexServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nex',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: nexLightTheme(),
      darkTheme: nexDarkTheme(),
      home: TimelineScreen(services: services),
    );
  }
}
