import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/keep_screen_on.dart';
import '../../platform/nex_preferences.dart';
import 'pause_art.dart';
import 'pause_patterns.dart';
import 'pause_sound.dart';

/// Where a session is.
enum _Stage { countdown, breathing, paused, done }

/// A breathing session: three seconds to settle, then the rounds, then a
/// bowl.
///
/// One clock drives everything — the drawing, the words, the taps — and the
/// sound is started on the same frame, so what is seen, felt and heard stay
/// together. Tapping the card pauses it; the screen stays lit while it runs.
///
/// The session also holds still when the world interrupts it: leaving the
/// app, the system taking the sound away, the back gesture or (on a keyboard)
/// the space bar all pause the breath rather than throwing it away, because a
/// session is the one screen in Nex whose whole point is being uninterrupted.
class PauseSession extends StatefulWidget {
  const PauseSession({
    super.key,
    required this.mode,
    required this.preferences,
    this.length = PauseLength.standard,
  });

  final PauseMode mode;
  final NexPreferences preferences;

  /// How long the session runs (2.8.14). The default keeps a session built
  /// before lengths existed breathing as many rounds as it always did.
  final PauseLength length;

  @override
  State<PauseSession> createState() => _PauseSessionState();
}

class _PauseSessionState extends State<PauseSession>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _countdown = Duration(seconds: 3);

  late final Ticker _ticker = createTicker(_tick);
  late final PauseSound _sound = pauseSoundFactory();
  late final FocusNode _keys = FocusNode(debugLabel: 'pause session');

  _Stage _stage = _Stage.countdown;

  /// The stage a pause came from, so a pause in the three seconds before the
  /// breathing can start the count again rather than half-finishing it.
  _Stage _pausedFrom = _Stage.breathing;

  StreamSubscription<void>? _interruptions;

  /// Time already spent in the current stage before the ticker last started.
  Duration _banked = Duration.zero;
  Duration _elapsed = Duration.zero;

  /// The last tap fired, so each one fires once: round, part, mark.
  (int, int, int)? _lastTap;
  int _lastCount = -1;
  int _countdownAttempt = 0;

  PauseMode get _mode => widget.mode;

  int get _rounds => widget.length.roundsFor(_mode);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sound.setMuted(!widget.preferences.pauseSound);
    _interruptions = _sound.interruptions.listen(
      (_) => _pauseSession(pauseAudio: false),
    );
    unawaited(NexKeepScreenOn.set(true));
    unawaited(_startCountdown());
  }

  Future<void> _startCountdown() async {
    final attempt = ++_countdownAttempt;
    _resetStage(_Stage.countdown);
    await _sound
        .prepare(_mode)
        .timeout(const Duration(milliseconds: 1500), onTimeout: () {});
    if (!mounted ||
        _stage != _Stage.countdown ||
        attempt != _countdownAttempt) {
      return;
    }
    unawaited(_sound.countdown());
    _ticker.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pauseSession();
  }

  void _pauseSession({bool pauseAudio = true}) {
    if (!mounted ||
        (_stage != _Stage.countdown && _stage != _Stage.breathing)) {
      return;
    }
    _ticker.stop();
    _pausedFrom = _stage;
    _banked = _elapsed;
    if (pauseAudio) unawaited(_sound.pause());
    setState(() => _stage = _Stage.paused);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_interruptions?.cancel());
    _interruptions = null;
    _keys.dispose();
    _ticker.dispose();
    unawaited(_sound.dispose());
    unawaited(NexKeepScreenOn.set(false));
    _restoreBars();
    super.dispose();
  }

  /// The bars go back to the app's own style, worked out the way `app.dart`
  /// works it out. This screen is the one place in Nex that is always dark,
  /// and without this the light icons it asked for would outlive it onto a
  /// light page (2.8.14).
  void _restoreBars() {
    final dark = switch (widget.preferences.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        // iOS reads the background it is drawn over rather than the icons.
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  void _tick(Duration sinceStart) {
    final elapsed = _banked + sinceStart;
    switch (_stage) {
      case _Stage.countdown:
        final second = elapsed.inSeconds;
        if (second != _lastCount && second < 3) {
          _lastCount = second;
          _tap(HapticFeedback.selectionClick);
        }
        if (elapsed >= _countdown) {
          _resetStage(_Stage.breathing);
          unawaited(_sound.startBreathing());
          _ticker.start();
          return;
        }
      case _Stage.breathing:
        final moment = pauseMomentAt(_mode, elapsed, rounds: _rounds);
        if (moment.done) {
          _ticker.stop();
          _tap(HapticFeedback.mediumImpact);
          unawaited(_sound.finish());
          setState(() => _stage = _Stage.done);
          return;
        }
        _guide(moment);
      case _Stage.paused || _Stage.done:
        return;
    }
    setState(() => _elapsed = elapsed);
  }

  void _resetStage(_Stage stage) {
    _ticker.stop();
    _banked = Duration.zero;
    _elapsed = Duration.zero;
    _lastTap = null;
    _lastCount = -1;
    setState(() => _stage = stage);
  }

  /// The taps that carry the breath to the hand.
  void _guide(PauseMoment moment) {
    final part = _mode.phases.indexOf(moment.phase);
    final marks = pauseTapsFor(moment.phase.step);
    var mark = -1;
    for (var i = 0; i < marks.length; i++) {
      if (moment.progress >= marks[i]) mark = i;
    }
    final at = (moment.round, part, mark);
    if (mark < 0 || at == _lastTap) return;
    _lastTap = at;
    _tap(
      mark == 0 ? HapticFeedback.lightImpact : HapticFeedback.selectionClick,
    );
  }

  void _tap(Future<void> Function() feedback) {
    if (widget.preferences.pauseHaptics) unawaited(feedback());
  }

  void _togglePause() {
    switch (_stage) {
      case _Stage.breathing:
        _pauseSession();
      case _Stage.paused:
        if (_pausedFrom == _Stage.countdown) {
          unawaited(_startCountdown());
          return;
        }
        setState(() => _stage = _Stage.breathing);
        unawaited(_sound.resume());
        _ticker.start();
      case _Stage.countdown || _Stage.done:
        break;
    }
  }

  /// Space or Enter does what a tap on the card does — for a desktop, and
  /// for anyone driving the session from a keyboard. A key held down arrives
  /// as its own KeyRepeatEvent, so this runs once per press.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (_stage != _Stage.breathing && _stage != _Stage.paused) {
      return KeyEventResult.ignored;
    }
    _togglePause();
    return KeyEventResult.handled;
  }

  Future<void> _setSound(bool on) async {
    _sound.setMuted(!on);
    await widget.preferences.setPauseSound(on);
    if (mounted) setState(() {});
  }

  Future<void> _setHaptics(bool on) async {
    await widget.preferences.setPauseHaptics(on);
    if (on) unawaited(HapticFeedback.lightImpact());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final showingBreath =
        _stage == _Stage.breathing ||
        (_stage == _Stage.paused && _pausedFrom == _Stage.breathing);
    final moment = showingBreath
        ? pauseMomentAt(_mode, _elapsed, rounds: _rounds)
        : null;
    final fullness = moment?.fullness ?? 0;
    final left = _stage == _Stage.done ? 0 : _rounds - (moment?.round ?? 0);
    final canToggle = _stage == _Stage.breathing || _stage == _Stage.paused;
    const white = Colors.white;
    final theme = Theme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // This one screen is dark in every theme, so it says so for itself:
      // the app paints the bars for its theme, and dark icons on the
      // session's near-black would vanish (2.8.14).
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: PopScope(
        canPop: _stage != _Stage.breathing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _stage == _Stage.breathing) _pauseSession();
        },
        child: Focus(
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Scaffold(
            backgroundColor: const Color(0xFF0D0E12),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexSpacing.lg,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: AspectRatio(
                            aspectRatio: 0.82,
                            child: Semantics(
                              // The card is one thing to a screen reader — its
                              // name, that it is a button, and what a tap does —
                              // and the word of the moment is announced inside it
                              // as its own live region, not folded into this
                              // name.
                              container: true,
                              explicitChildNodes: true,
                              button: canToggle,
                              label: _name(l10n),
                              hint: canToggle ? l10n.pauseCardAction : null,
                              onTap: canToggle ? _togglePause : null,
                              child: GestureDetector(
                                key: const ValueKey('pause-card'),
                                behavior: HitTestBehavior.opaque,
                                onTap: _togglePause,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    NexRadius.xl * 2,
                                  ),
                                  child: CustomPaint(
                                    painter: PauseSkyPainter(
                                      palette: PausePalette.of(_mode),
                                      fullness: fullness,
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: AnimatedOpacity(
                                            opacity: _stage == _Stage.paused
                                                ? 0.4
                                                : 1,
                                            duration: NexMotion.of(
                                              context,
                                              NexMotion.standard,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                NexSpacing.xl,
                                              ),
                                              child: CustomPaint(
                                                painter: PauseArtPainter(
                                                  mode: _mode,
                                                  fullness:
                                                      _stage == _Stage.done
                                                      ? 0.5
                                                      : fullness,
                                                  seconds:
                                                      _elapsed.inMilliseconds /
                                                      1000,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        PositionedDirectional(
                                          top: NexSpacing.lg,
                                          start: NexSpacing.lg,
                                          end: NexSpacing.lg,
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  _name(l10n),
                                                  style: theme
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(color: white),
                                                ),
                                              ),
                                              Semantics(
                                                label: l10n.pauseBreathsLeft(
                                                  nexDigits(
                                                    '$left',
                                                    persian: persian,
                                                  ),
                                                ),
                                                excludeSemantics: true,
                                                child: Text(
                                                  nexDigits(
                                                    '$left',
                                                    persian: persian,
                                                  ),
                                                  key: const ValueKey(
                                                    'pause-left',
                                                  ),
                                                  style: theme
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        color: white.withValues(
                                                          alpha: 0.85,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Center(
                                          child: _centre(context, l10n, moment),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _controls(context, l10n),
                  const SizedBox(height: NexSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _name(AppLocalizations l10n) => switch (_mode) {
    PauseMode.calm => l10n.pauseModeCalm,
    PauseMode.focus => l10n.pauseModeFocus,
    PauseMode.relax => l10n.pauseModeRelax,
  };

  String _word(AppLocalizations l10n, PauseMoment? moment) => switch (_stage) {
    _Stage.paused => l10n.pausePaused,
    _Stage.done => l10n.pauseDoneTitle,
    _Stage.countdown => '',
    _Stage.breathing => switch (moment!.phase.step) {
      PauseStep.inhale => l10n.pauseInhale,
      PauseStep.exhale => l10n.pauseExhale,
      PauseStep.holdFull || PauseStep.holdEmpty => l10n.pauseHold,
    },
  };

  /// The words in the middle: the count, the breath, or the end. Each one is
  /// said aloud as it changes, so a session can be followed by ear alone.
  Widget _centre(
    BuildContext context,
    AppLocalizations l10n,
    PauseMoment? moment,
  ) {
    final theme = Theme.of(context);
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    // A soft shadow keeps the words readable where a line of the drawing
    // passes behind them.
    const lift = [Shadow(color: Color(0x66000000), blurRadius: 12)];
    final big = theme.textTheme.headlineMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w400,
      shadows: lift,
    );
    final small = theme.textTheme.bodyMedium?.copyWith(
      color: Colors.white.withValues(alpha: 0.85),
      shadows: lift,
    );
    // The words give way before the drawing does: a huge text scale, or a
    // window that leaves the card short, shrinks them to what fits.
    Widget fitted(Key key, Widget child) =>
        FittedBox(key: key, fit: BoxFit.scaleDown, child: child);
    final Widget child = switch (_stage) {
      _Stage.countdown => fitted(
        const ValueKey('count'),
        Text(
          nexDigits('${3 - _elapsed.inSeconds.clamp(0, 2)}', persian: persian),
          key: const ValueKey('pause-count'),
          style: big,
        ),
      ),
      _Stage.breathing => fitted(
        ValueKey(_word(l10n, moment)),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              // Its own node, so what it says is announced on its own and
              // not folded into the card's name.
              container: true,
              liveRegion: true,
              label: _word(l10n, moment),
              child: ExcludeSemantics(
                child: Text(_word(l10n, moment), style: big),
              ),
            ),
            if (moment!.phase.step == PauseStep.holdFull ||
                moment.phase.step == PauseStep.holdEmpty)
              Text(
                nexDigits('${moment.secondsLeft}', persian: persian),
                style: small,
              ),
          ],
        ),
      ),
      _Stage.paused => fitted(
        const ValueKey('paused'),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.pausePaused, style: big),
            const SizedBox(height: NexSpacing.xs),
            Text(l10n.pauseTapToResume, style: small),
          ],
        ),
      ),
      _Stage.done => fitted(
        const ValueKey('done'),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.pauseDoneTitle, style: big),
            const SizedBox(height: NexSpacing.xs),
            Text(
              l10n.pauseDoneBody(
                nexDigits('$_rounds', persian: persian),
                pauseLength(widget.length.durationOf(_mode), persian: persian),
              ),
              style: small,
            ),
          ],
        ),
      ),
    };
    return AnimatedSwitcher(
      duration: NexMotion.of(context, NexMotion.standard),
      child: child,
    );
  }

  Widget _controls(BuildContext context, AppLocalizations l10n) {
    final sound = widget.preferences.pauseSound;
    final haptics = widget.preferences.pauseHaptics;
    final quiet = Colors.white.withValues(alpha: 0.7);
    Widget round({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      Key? key,
      double size = 56,
    }) => Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        onTap: onPressed,
        excludeSemantics: true,
        child: Material(
          key: key,
          color: Colors.white.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, color: Colors.white),
            ),
          ),
        ),
      ),
    );

    if (_stage == _Stage.done) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: FilledButton.tonalIcon(
              key: const ValueKey('pause-again'),
              onPressed: () => unawaited(_startCountdown()),
              icon: const Icon(Icons.replay),
              label: Text(l10n.pauseAgain),
            ),
          ),
          const SizedBox(width: NexSpacing.md),
          round(
            key: const ValueKey('pause-close'),
            icon: Icons.close,
            tooltip: l10n.closeLabel,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const ValueKey('pause-sound'),
          tooltip: sound ? l10n.pauseSoundOn : l10n.pauseSoundOff,
          onPressed: () => unawaited(_setSound(!sound)),
          icon: Icon(
            sound ? Icons.volume_up_outlined : Icons.volume_off_outlined,
            color: quiet,
          ),
        ),
        const SizedBox(width: NexSpacing.xl),
        round(
          key: const ValueKey('pause-close'),
          icon: Icons.close,
          tooltip: l10n.pauseEnd,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: NexSpacing.xl),
        IconButton(
          key: const ValueKey('pause-haptics'),
          tooltip: haptics ? l10n.pauseHapticsOn : l10n.pauseHapticsOff,
          onPressed: () => unawaited(_setHaptics(!haptics)),
          icon: Icon(
            haptics ? Icons.vibration : Icons.mobile_off_outlined,
            color: quiet,
          ),
        ),
      ],
    );
  }
}

/// "1:50", or "۱:۵۰": a session's length the way a timer shows it.
String pauseLength(Duration length, {required bool persian}) {
  final seconds = length.inSeconds % 60;
  return nexDigits(
    '${length.inMinutes}:${seconds.toString().padLeft(2, '0')}',
    persian: persian,
  );
}
