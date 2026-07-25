import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nex_ui/nex_ui.dart';

import 'l10n/app_localizations.dart';
import 'platform/nex_preferences.dart';
import 'platform/nex_services.dart';
import 'platform/os_capture_bridge.dart';
import 'screens/timeline_screen.dart';

/// Nex application shell (Phase 1.x).
class NexApp extends StatefulWidget {
  const NexApp({
    super.key,
    required this.services,
    required this.preferences,
    this.osCapture,
    this.openTextCaptureOnLaunch = false,
  });

  final NexServices services;
  final NexPreferences preferences;
  final OsCaptureBridge? osCapture;
  final bool openTextCaptureOnLaunch;

  @override
  State<NexApp> createState() => _NexAppState();
}

class _NexAppState extends State<NexApp> {
  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onPrefs);
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onPrefs);
    super.dispose();
  }

  void _onPrefs() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final comfort = widget.preferences.comfortMode;
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: nexLightTheme(comfortMode: comfort),
      darkTheme: nexDarkTheme(comfortMode: comfort),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: TimelineScreen(
        services: widget.services,
        preferences: widget.preferences,
        osCapture: widget.osCapture,
        openTextCaptureOnLaunch: widget.openTextCaptureOnLaunch,
      ),
    );
  }
}
