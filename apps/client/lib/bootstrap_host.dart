import 'dart:async';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'l10n/app_localizations.dart';
import 'platform/nex_preferences.dart';
import 'platform/nex_services.dart';
import 'platform/os_capture_bridge.dart';
import 'platform/share_window.dart';
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
  late Future<_Ready> _future;
  _Ready? _ready;

  /// Whether this launch is the invisible window a share arrives through.
  ///
  /// Asked once, before anything is drawn, because the answer decides whether
  /// anything is drawn at all — see [build]. Null until the platform has
  /// answered, which is a third state and not a default: painting the wordmark
  /// while the question is outstanding is the one frame this exists to avoid.
  late final Future<bool> _silentFuture = NexShareWindow.isSilent();
  bool? _silent;

  @override
  void initState() {
    super.initState();
    // Started here rather than lazily from `build`. The silent share window
    // never builds anything at all, and the note still has to be written: a
    // `late` field initialised on first read would simply never run there.
    _future = _start();
    unawaited(
      _silentFuture.then((value) {
        if (mounted) setState(() => _silent = value);
      }),
    );
  }

  Future<_Ready> _start() async {
    final silent = await _silentFuture;
    // The floor exists so a warm start does not flash the brand mark for one
    // frame. A window that never draws has no mark to flash, and holding it
    // open for another nine hundred milliseconds is nine hundred milliseconds
    // before the person is told their note was saved.
    final delay = silent
        ? Future<void>.value()
        : Future<void>.delayed(_minimumSplashDuration);

    final preferences = await NexPreferences.load();
    final services = await NexServices.bootstrap(preferences: preferences);
    services.applyAiPreferences(preferences);

    final bridge = OsCaptureBridge(services);
    // A share that fails must not look like a library that will not open.
    //
    // `start()` drains whatever the OS queued, and draining it means running
    // the capture. Anything that throws in there — reported as an
    // out-of-memory while finishing a two-gigabyte video share — used to
    // propagate straight out of here, so the app opened on "Nex could not
    // open your local library. Your files were not changed", and offered
    // Restore backup as the way out. The library was never touched, and
    // restoring one over it is the single worst thing that screen could have
    // talked someone into.
    //
    // The share is lost either way; what changes is that the app opens, and
    // the reason is written where "Share diagnostics" will find it.
    try {
      await bridge.start();
    } catch (error) {
      unawaited(NexServices.noteDiagnostic('shared capture failed: $error'));
    }

    if (silent) await _closeSilently(bridge, preferences);

    await delay;
    return _ready = _Ready(preferences, services, bridge);
  }

  /// Says what became of the share and takes the window down.
  ///
  /// The whole of what a person sees when they share into Nex: a toast, over
  /// the app they were already using. There is no screen to put a banner on
  /// here and deliberately so — see [NexShareWindow].
  ///
  /// The localisations are loaded directly rather than read off a
  /// `BuildContext`, because this runs during bootstrap and there is no
  /// context, and never will be one on this path. The locale is Nex's own
  /// setting when there is one: the platform would otherwise answer the
  /// device's, which is a different question.
  Future<void> _closeSilently(
    OsCaptureBridge bridge,
    NexPreferences preferences,
  ) async {
    final refused = bridge.pendingRejection;
    if (refused == null && !bridge.handledLaunchShare) {
      // Nothing arrived. Nothing to say, and nothing to keep the window open
      // for either — an empty message still closes it.
      await NexShareWindow.done('');
      return;
    }
    final l10n = await AppLocalizations.delegate.load(
      _messageLocale(preferences),
    );
    final message = refused == null
        ? l10n.shareSaved
        : l10n.shareTooLarge(
            refused.filename,
            nexFormatBytes(refused.bytes),
            nexFormatBytes(refused.limit),
          );
    // Only once the platform confirms the window is really going. If it is
    // not — this was the ordinary app after all — the refusal is still owed to
    // the timeline, which reads it with `takeRejection` of its own.
    if (await NexShareWindow.done(message)) bridge.takeRejection();
  }

  /// Which language to say it in: Nex's own setting, or the closest the device
  /// asks for among the ones Nex ships.
  Locale _messageLocale(NexPreferences preferences) {
    final chosen = preferences.locale;
    if (chosen != null) return chosen;
    final asked = WidgetsBinding.instance.platformDispatcher.locales;
    for (final locale in asked) {
      for (final supported in AppLocalizations.supportedLocales) {
        if (supported.languageCode == locale.languageCode) return supported;
      }
    }
    return AppLocalizations.supportedLocales.first;
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
  Widget build(BuildContext context) {
    // Nothing, until the platform has said which kind of window this is — and
    // nothing ever, if it is the silent one. A share is received behind
    // whatever app the person was using, and a single frame of Nex painted
    // over it is the whole of what this avoids. The unresolved case is the
    // same answer: two frames of nothing on an ordinary launch sit under
    // Android's own starting window and are never seen.
    if (_silent != false) return const SizedBox.shrink();
    return _app();
  }

  Widget _app() => FutureBuilder<_Ready>(
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
          child: _OpenFailed(
            error: snapshot.error,
            onRetry: () => setState(() => _future = _start()),
            onRestored: _restart,
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

/// The screen a person sees when the library will not open.
///
/// It used to be one sentence and a Try again button — which was honest about
/// the failure but useless against its most common cause, a database file
/// that will not open. The restore path is offered right here because it is
/// the one path that does not need the worker: [NexBackupArchive.restore]
/// works on the files directly, so a corrupt `nex.sqlite` can be replaced
/// with a good `.nexbak` without the app ever having opened. The real error
/// text is shown because "could not open your library" repeated forever with
/// no reason is how a support ticket gets written, not answered.
class _OpenFailed extends StatelessWidget {
  const _OpenFailed({
    required this.error,
    required this.onRetry,
    required this.onRestored,
  });

  /// What bootstrap actually threw.
  final Object? error;

  final VoidCallback onRetry;

  /// Called after a backup was restored over the dead library.
  final VoidCallback onRestored;

  Future<void> _restore(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Nex backup', extensions: ['nexbak', 'sqlite']),
      ],
    );
    if (file == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      // Same composition as NexServices.bootstrap computes — this screen
      // exists precisely when no services object does.
      final support = await getApplicationSupportDirectory();
      final dbPath = p.join(support.path, 'nex.sqlite');
      final mediaDir = p.join(support.path, 'media');
      await Isolate.run(
        () => NexBackupArchive.restore(
          liveDbPath: dbPath,
          mediaDir: mediaDir,
          backupFile: file.path,
        ),
      );
      onRestored();
    } on Object catch (restoreError) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.restoreFailed('$restoreError'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Wordmark(),
              const SizedBox(height: 16),
              Text(l10n.libraryOpenFailed, textAlign: TextAlign.center),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.libraryOpenDetail('$error'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: Text(l10n.tryAgain)),
              const SizedBox(height: 8),
              Text(
                l10n.restoreBackupHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => unawaited(_restore(context)),
                child: Text(l10n.restoreBackup),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ready {
  const _Ready(this.preferences, this.services, this.bridge);

  final NexPreferences preferences;
  final NexServices services;
  final OsCaptureBridge bridge;
}
