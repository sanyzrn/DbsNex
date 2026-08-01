import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import 'app.dart';
import 'l10n/app_localizations.dart';
import 'platform/nex_preferences.dart';
import 'platform/nex_services.dart';
import 'platform/os_capture_bridge.dart';
import 'restart_scope.dart';

class NexBootstrapHost extends StatefulWidget {
  const NexBootstrapHost({super.key});

  @override
  State<NexBootstrapHost> createState() => _NexBootstrapHostState();
}

/// Floor on how briefly the splash can appear.
///
/// A warm start resolves [_NexBootstrapHostState._start] fast enough that the
/// brand mark was often a single flashed frame — not a deliberate choice, just
/// whatever [NexServices.bootstrap] happened to take. This never adds latency
/// beyond that: it races the real work against a timer and waits for whichever
/// finishes last, so a slow cold start is never held up by it.
const _minimumSplashDuration = Duration(milliseconds: 900);

class _NexBootstrapHostState extends State<NexBootstrapHost> {
  late Future<_Ready> _future = _start();
  _Ready? _ready;

  Future<_Ready> _start() async {
    final delay = Future<void>.delayed(_minimumSplashDuration);

    final preferences = await NexPreferences.load();
    final services = await NexServices.bootstrap(preferences: preferences);
    services.applyAiPreferences(preferences);

    final bridge = OsCaptureBridge(services);
    await bridge.start();

    await delay;
    return _ready = _Ready(preferences, services, bridge);
  }

  /// Teardown is asynchronous now (the worker isolate must be joined). It must
  /// not block the rebuild and must never throw into the widget tree.
  void _teardown(_Ready? target) {
    if (target == null) return;
    target.bridge.dispose();
    target.services.dispose().catchError((Object _) {});
  }

  void _restart() {
    final previous = _ready;
    _ready = null;
    _teardown(previous);
    setState(() => _future = _start());
  }

  @override
  void dispose() {
    _teardown(_ready);
    _ready = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Ready>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        final value = snapshot.requireData;
        return NexRestartScope(
          restart: _restart,
          child: NexApp(
            services: value.services,
            preferences: value.preferences,
            osCapture: value.bridge,
          ),
        );
      }

      if (snapshot.hasError) {
        return _host(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(NexSpacing.lg),
                child: Builder(
                  builder: (context) {
                    final l10n = AppLocalizations.of(context);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _Wordmark(),
                        const SizedBox(height: 16),
                        Text(
                          l10n.libraryOpenFailed,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => setState(() => _future = _start()),
                          child: Text(l10n.tryAgain),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      }

      return _host(
        child: Center(
          child: Builder(
            builder: (context) => Semantics(
              label: AppLocalizations.of(context).opening,
              child: const _Wordmark(),
            ),
          ),
        ),
      );
    },
  );

  /// The pre-boot shells carry the localization delegates themselves.
  ///
  /// They render before [NexApp] exists, so without this the one screen a user
  /// sees when their library fails to open was permanently English.
  Widget _host({required Widget child}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: nexLightTheme(),
    darkTheme: nexDarkTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => Image.asset(
    Theme.of(context).brightness == Brightness.dark
        ? 'assets/branding/dark_splash.png'
        : 'assets/branding/light_splash.png',
    width: 192,
    semanticLabel: 'Nex',
  );
}

class _Ready {
  const _Ready(this.preferences, this.services, this.bridge);

  final NexPreferences preferences;
  final NexServices services;
  final OsCaptureBridge bridge;
}
