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
import 'screens/timeline_screen.dart';
import 'widgets/nex_toast.dart';

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

  /// So a toast can be raised from a listener, above any screen's own context.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  late final UpdateService _updates = UpdateService(
    preferences: widget.preferences,
  );

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_refresh);
    _updates.addListener(_announceDownload);
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
    _updates.removeListener(_announceDownload);
    _updates.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  /// Says so, once, when an installer finishes arriving.
  ///
  /// The download survives leaving the update screen now, which means it
  /// usually finishes while the user is somewhere else — and something that
  /// completes invisibly may as well not have happened. This is the one place
  /// the update flow is allowed to speak unprompted, and it is a toast that
  /// fades on its own rather than anything that has to be dismissed.
  void _announceDownload() {
    if (!_updates.hasUnannouncedDownload) return;
    final messenger = _messengerKey.currentState;
    final context = _messengerKey.currentContext;
    if (messenger == null || context == null) return;
    _updates.markAnnounced();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        nexToast(
          duration: const Duration(seconds: 4),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_done,
                size: 20,
                color: scheme.onInverseSurface,
              ),
              const SizedBox(width: NexSpacing.md),
              Flexible(child: Text(l10n.updateDownloadedToast)),
            ],
          ),
        ),
      );
  }

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
    final accentSeed = nexParseTagColor(prefs.accentSeed);
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: prefs.locale,
      themeMode: prefs.themeMode,
      theme: nexLightTheme(
        comfortMode: prefs.comfortMode,
        fontFamily: font,
        accentSeed: accentSeed,
      ),
      darkTheme: nexDarkTheme(
        comfortMode: prefs.comfortMode,
        fontFamily: font,
        accentSeed: accentSeed,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        // The user's own multiplier composes with the system's, rather than
        // replacing it — someone with a larger system font can still nudge
        // Nex a little further in either direction on top of that. The floor
        // and ceiling widen from the system-only clamp below to leave that
        // combination room to actually move.
        final scaled =
            TextScaler.linear(prefs.uiScale).scale(1) *
            media.textScaler.scale(1);
        return MediaQuery(
          data: media.copyWith(
            disableAnimations: prefs.reduceMotion || media.disableAnimations,
            textScaler: TextScaler.linear(
              scaled,
            ).clamp(minScaleFactor: 0.75, maxScaleFactor: 1.9),
          ),
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyN, control: true):
                  _CaptureIntent(),
              SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  _SearchIntent(),
            },
            child: Actions(
              actions: {
                _CaptureIntent: CallbackAction<_CaptureIntent>(
                  onInvoke: (_) => timelineKey.currentState?.openCapture(),
                ),
                // Reveals the field on the timeline rather than pushing a
                // screen: search is one surface now, and Ctrl+F should land on
                // the same one the pull-down does.
                _SearchIntent: CallbackAction<_SearchIntent>(
                  onInvoke: (_) => timelineKey.currentState?.revealSearch(),
                ),
              },
              // A bare Scaffold above the Navigator, not inside it. Every
              // screen's own Scaffold is nested under this one, and
              // ScaffoldMessenger shows a SnackBar on only the root of a
              // nested set — so toasts now paint above whatever the
              // Navigator is showing, dialog or bottom sheet included,
              // instead of being scoped to whichever page happened to be
              // underneath when they were raised.
              child: Scaffold(
                backgroundColor: Colors.transparent,
                resizeToAvoidBottomInset: false,
                body: FocusTraversalGroup(child: child!),
              ),
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

class _CaptureIntent extends Intent {
  const _CaptureIntent();
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}
