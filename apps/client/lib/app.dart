import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nex_ui/nex_ui.dart';
import 'l10n/app_localizations.dart';
import 'platform/nex_preferences.dart';
import 'platform/nex_services.dart';
import 'platform/os_capture_bridge.dart';
import 'platform/update_service.dart';
import 'screens/search_screen.dart';
import 'screens/timeline_screen.dart';

class NexApp extends StatefulWidget {
  const NexApp({
    super.key,
    required this.services,
    required this.preferences,
    this.osCapture,
  });
  final NexServices services;
  final NexPreferences preferences;
  final OsCaptureBridge? osCapture;
  @override
  State<NexApp> createState() => _NexAppState();
}

class _NexAppState extends State<NexApp> with WidgetsBindingObserver {
  final timelineKey = GlobalKey<TimelineScreenState>();
  late final UpdateService _updates =
      UpdateService(preferences: widget.preferences);

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_refresh);
    // Quietly, on launch and whenever the app comes back — at most once a day.
    // Nothing interrupts: the only outcome a user ever sees is a dot on the
    // settings icon.
    WidgetsBinding.instance.addObserver(this);
    unawaited(_updates.maybeCheck());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_updates.maybeCheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.preferences.removeListener(_refresh);
    _updates.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  /// What the device would pick when the user has not chosen a language.
  ///
  /// `Localizations.localeOf` is not available above the [MaterialApp], so the
  /// platform's own preference is resolved against the locales this app
  /// actually ships.
  Locale? _systemLocale(BuildContext context) {
    for (final locale in View.of(context).platformDispatcher.locales) {
      for (final supported in AppLocalizations.supportedLocales) {
        if (supported.languageCode == locale.languageCode) return supported;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.preferences;
    // Persian is set in Vazirmatn, everything else in Inter. Following the
    // chosen locale rather than the note's own script is deliberate: this is
    // the interface's face, and a Persian note inside an English UI keeps its
    // direction (see NexBodyText) without dragging the whole chrome with it.
    final font = nexFontFor(prefs.locale ?? _systemLocale(context));
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: prefs.locale,
      themeMode: prefs.themeMode,
      theme: nexLightTheme(comfortMode: prefs.comfortMode, fontFamily: font),
      darkTheme: nexDarkTheme(comfortMode: prefs.comfortMode, fontFamily: font),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            disableAnimations: prefs.reduceMotion || media.disableAnimations,
            textScaler: media.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.6),
          ),
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyN, control: true): _CaptureIntent(),
              SingleActivator(LogicalKeyboardKey.keyF, control: true): _SearchIntent(),
            },
            child: Actions(
              actions: {
                _CaptureIntent: CallbackAction<_CaptureIntent>(
                  onInvoke: (_) => timelineKey.currentState?.openCapture(),
                ),
                _SearchIntent: CallbackAction<_SearchIntent>(
                  onInvoke: (_) => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SearchScreen(services: widget.services),
                    ),
                  ),
                ),
              },
              child: FocusTraversalGroup(child: child!),
            ),
          ),
        );
      },
      home: TimelineScreen(
        key: timelineKey,
        services: widget.services,
        preferences: prefs,
        osCapture: widget.osCapture,
        updates: _updates,
      ),
    );
  }
}

class _CaptureIntent extends Intent { const _CaptureIntent(); }
class _SearchIntent extends Intent { const _SearchIntent(); }