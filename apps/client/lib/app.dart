import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nex_ui/nex_ui.dart';
import 'l10n/app_localizations.dart';
import 'platform/route_observer.dart';
import 'platform/app_lock.dart';
import 'platform/download_notice.dart';
import 'platform/feedback_service.dart';
import 'platform/nex_preferences.dart';
import 'platform/nex_services.dart';
import 'platform/os_capture_bridge.dart';
import 'platform/secure_window.dart';
import 'platform/update_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/timeline_screen.dart';
import 'widgets/nex_banner.dart';

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
    onDownloadStatus: _showDownloadNotification,
  );
  late final _feedback = FeedbackService(preferences: widget.preferences);
  final _appLock = AppLockService();
  bool _locked = false;
  bool _unlocking = false;

  /// What the window flag was last set to, so that a preference change with
  /// nothing to do with the lock — every one of them arrives at [_refresh] —
  /// does not go back to the platform to say the same thing again.
  bool? _secureWindow;

  @override
  void initState() {
    super.initState();
    _locked = widget.preferences.appLockEnabled;
    _applyWindowSecrecy();
    widget.preferences.addListener(_refresh);
    _updates.addListener(_announceDownload);
    // Quietly, on launch and whenever the app comes back — at most once a day.
    // Nothing interrupts: the only outcome a user ever sees is a dot on the
    // settings icon.
    WidgetsBinding.instance.addObserver(this);
    unawaited(_updates.maybeCheck());
    // Feedback that failed to send while offline retries here rather than on
    // a connectivity listener this app does not have — coming back to the
    // app is, in practice, also when a phone that regained signal while
    // backgrounded gets noticed.
    unawaited(_feedback.flushPending());
    // Alarms are not durable and notes are. A reinstall, a restore from
    // backup, or an OS that dropped its alarm list all leave reminders that
    // exist on the note and nowhere else — so every launch puts them back
    // from the library, which is the only copy that survives.
    unawaited(widget.services.restoreReminders());
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        widget.preferences.appLockEnabled &&
        !_unlocking &&
        mounted) {
      setState(() => _locked = true);
    }
    if (state == AppLifecycleState.resumed) {
      if (_locked) unawaited(_unlock());
      unawaited(_updates.maybeCheck());
      // Android stops the process shortly after the app leaves the screen,
      // and an installer being fetched stops with it. This is the moment it
      // can carry on — by range, from where it got to, so the wait is the
      // only thing that was lost.
      unawaited(_updates.resumeInterruptedDownload());
      unawaited(_feedback.flushPending());
      // Alarms are not durable and notes are. A reinstall, a restore from
      // backup, or an OS that dropped its alarm list all leave reminders that
      // exist on the note and nowhere else — so every launch puts them back
      // from the library, which is the only copy that survives.
      unawaited(widget.services.restoreReminders());
      // Re-read the library on the way back in. This is what pull-to-refresh
      // was standing in for, and it is strictly better at the job: every
      // capture path already re-fires the timeline stream itself, so the only
      // way the list can be stale is that something wrote a note while this
      // screen was not running — and coming back is exactly when that is
      // true, and exactly when a user would not think to pull.
      unawaited(widget.services.refreshTimeline());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.preferences.removeListener(_refresh);
    _updates.removeListener(_announceDownload);
    _updates.dispose();
    _feedback.close();
    super.dispose();
  }

  void _refresh() {
    if (!widget.preferences.appLockEnabled) _locked = false;
    _applyWindowSecrecy();
    setState(() {});
  }

  /// Follows the app lock, on and off.
  ///
  /// The lock stops someone opening the app. On its own it does nothing about
  /// the copy of the timeline Android keeps for the recents screen — which is
  /// a picture of the notes, taken before the lock gate was ever drawn, and
  /// readable without unlocking anything. `FLAG_SECURE` is what blanks it, and
  /// blocks screenshots while it is on.
  ///
  /// Not always on: someone who never turned the lock on has not asked to lose
  /// screenshots of their own notes. Turning it on is the point at which the
  /// user has said these are private.
  void _applyWindowSecrecy() {
    final wanted = widget.preferences.appLockEnabled;
    if (_secureWindow == wanted) return;
    _secureWindow = wanted;
    unawaited(NexSecureWindow.setSecure(wanted));
  }

  Future<void> _unlock() async {
    if (!_locked || _unlocking || !mounted) return;
    final context = _messengerKey.currentContext;
    if (context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
      return;
    }
    _unlocking = true;
    final unlocked = await _appLock.authenticate(
      reason: AppLocalizations.of(context).securityAuthenticateReason,
      biometricOnly: widget.preferences.appLockBiometricOnly,
    );
    _unlocking = false;
    if (mounted && unlocked) setState(() => _locked = false);
  }

  /// Puts the download in the notification shade, where it can be watched
  /// without this app being open.
  ///
  /// Here rather than in the service because the strings are localised and
  /// the service has no `BuildContext` — and should not grow one to post a
  /// notification. The messenger's context sits under [MaterialApp], which is
  /// as much as `AppLocalizations` needs.
  ///
  /// A stopped download takes its entry down rather than replacing it with a
  /// second kind of notification: resuming lives on the update screen, and a
  /// shade entry that only says "something went wrong" is noise.
  void _showDownloadNotification(NexDownloadStatus status) {
    final context = _messengerKey.currentContext;
    if (context == null) return;
    final l10n = AppLocalizations.of(context);
    final reminders = widget.services.reminders;
    switch (status.stage) {
      case NexDownloadStage.running:
        unawaited(
          _reportDownload(l10n.updateDownloadingTitle, status.percent ?? 0),
        );
      case NexDownloadStage.done:
        // The service goes first: its notification is the progress bar, and
        // the one below is the tappable "ready to install" that has to
        // outlive it.
        unawaited(NexDownloadNotice.hide());
        unawaited(
          reminders.showDownloadReady(
            title: l10n.updateReadyTitle,
            body: l10n.updateReadyBody,
          ),
        );
      case NexDownloadStage.stopped:
        unawaited(NexDownloadNotice.hide());
        unawaited(reminders.clearDownloadNotification());
    }
  }

  /// Puts the progress in the shade, by whichever half of the app can.
  ///
  /// On Android that is a foreground service, because the notification is not
  /// the point of it — keeping the process running while the transfer
  /// continues is, and only a service does that. Where there is no service,
  /// the app posts the notification itself, which is all this ever was.
  Future<void> _reportDownload(String title, int percent) async {
    if (await NexDownloadNotice.show(title: title, percent: percent)) return;
    await widget.services.reminders.showDownloadProgress(
      title: title,
      percent: percent,
    );
  }

  /// Says so, once, when an installer finishes arriving.
  ///
  /// The download survives leaving the update screen now, which means it
  /// usually finishes while the user is somewhere else — and something that
  /// completes invisibly may as well not have happened. This is the one place
  /// the update flow is allowed to speak unprompted, and it is a toast that
  /// fades on its own rather than anything that has to be dismissed.
  void _announceDownload() {
    if (!_updates.hasUnannouncedDownload) return;
    final context = _messengerKey.currentContext;
    if (context == null) return;
    _updates.markAnnounced();
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).updateDownloadedToast,
      haptics: widget.preferences.haptics,
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
    // Kept in step here rather than read at each call site: every widget that
    // buzzes would otherwise need preferences in scope to answer a question
    // the whole app answers the same way. This rebuilds on every preference
    // change, which is exactly when the answer can move.
    nexHapticsEnabled = widget.preferences.haptics;
    final prefs = widget.preferences;
    // Persian is set in Vazirmatn, everything else in Inter. Following the
    // chosen locale rather than the note's own script is deliberate: this is
    // the interface's face, and a Persian note inside an English UI keeps its
    // direction (see NexBodyText) without dragging the whole chrome with it.
    final font = nexFontFor(prefs.locale ?? _systemLocale(context));
    final accentSeed = nexParseTagColor(prefs.accentSeed);
    final transparentScaffold =
        prefs.liquidGlass ||
        prefs.backgroundPattern != NexBackgroundPattern.plain;
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      // The timeline listens on this to know when it has been covered and
      // uncovered again — which is what "you have seen that reminder" means.
      navigatorObservers: [nexRouteObserver],
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: prefs.locale,
      themeMode: prefs.themeMode,
      themeAnimationDuration: NexMotion.slow,
      themeAnimationCurve: NexMotion.curve,
      theme: nexLightTheme(
        comfortMode: prefs.comfortMode,
        liquidGlass: prefs.liquidGlass,
        transparentScaffold: transparentScaffold,
        fontFamily: font,
        accentSeed: accentSeed,
      ),
      darkTheme: nexDarkTheme(
        comfortMode: prefs.comfortMode,
        liquidGlass: prefs.liquidGlass,
        transparentScaffold: transparentScaffold,
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
        return NexAppBackground(
          pattern: prefs.backgroundPattern,
          child: MediaQuery(
            data: media.copyWith(
              disableAnimations: media.disableAnimations,
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
                child: Stack(
                  children: [
                    Scaffold(
                      backgroundColor: Colors.transparent,
                      resizeToAvoidBottomInset: false,
                      body: ExcludeSemantics(
                        excluding: _locked,
                        child: IgnorePointer(
                          ignoring: _locked,
                          child: FocusTraversalGroup(child: child!),
                        ),
                      ),
                    ),
                    if (_locked)
                      Positioned.fill(
                        child: _AppLockGate(
                          busy: _unlocking,
                          onUnlock: () => unawaited(_unlock()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      // Swapped rather than pushed: onboarding is not a screen you can come
      // back from, and a route stacked over the timeline would leave the
      // system back gesture skipping past it into an app that has not been
      // told the user's name yet. Finishing writes the preference, which
      // notifies, which rebuilds this — see [_refresh].
      home: prefs.onboardingComplete
          ? TimelineScreen(
              key: timelineKey,
              services: widget.services,
              preferences: prefs,
              osCapture: widget.osCapture,
              updates: _updates,
            )
          : OnboardingScreen(preferences: prefs),
    );
  }
}

class _CaptureIntent extends Intent {
  const _CaptureIntent();
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

/// The opaque sheet the lock gate paints over the app.
///
/// Named so a test can find it and check that it is still opaque — which is
/// the whole of the bug it exists for.
@visibleForTesting
const appLockBarrierKey = Key('nex.app-lock-barrier');

class _AppLockGate extends StatelessWidget {
  const _AppLockGate({required this.busy, required this.onUnlock});

  final bool busy;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Its own colour, not the theme's scaffold background, and forced opaque.
    //
    // `scaffoldBackgroundColor` is `Colors.transparent` whenever liquid glass
    // or a background pattern is on — deliberately, so the app's backdrop
    // shows through every screen — and a bare `Scaffold` here inherited that.
    // The result was a lock gate you could read the timeline through while it
    // waited for a fingerprint: every note on screen, behind the prompt that
    // was supposedly hiding them.
    //
    // `canvasColor` is the page background with no glass applied, which is the
    // right shade; the alpha is pinned anyway so that no future theme can make
    // this see-through again without failing a test.
    final barrier = theme.canvasColor.withValues(alpha: 1);
    return Scaffold(
      key: appLockBarrierKey,
      backgroundColor: barrier,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: NexSpacing.md),
              Text(
                l10n.securityLockedTitle,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: NexSpacing.sm),
              Text(
                l10n.securityLockedSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: NexSpacing.lg),
              FilledButton.icon(
                onPressed: busy ? null : onUnlock,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(l10n.securityUnlock),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
