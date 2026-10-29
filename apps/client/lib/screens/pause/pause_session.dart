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
class PauseSession extends StatefulWidget {
  const PauseSession({
    super.key,
    required this.mode,
    required this.preferences,
  });

  final PauseMode mode;
  final NexPreferences preferences;

  @override
  State<PauseSession> createState() => _PauseSessionState();
}

class _PauseSessionState extends State<PauseSession>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _countdown = Duration(seconds: 3);

  late final Ticker _ticker = createTicker(_tick);
  late final PauseSound _sound = pauseSoundFactory();

  _Stage _stage = _Stage.countdown;

  /// Time already spent in the current stage before the ticker last started.
  Duration _banked = Duration.zero;
  Duration _elapsed = Duration.zero;

  /// The last tap fired, so each one fires once: round, part, mark.
  (int, int, int)? _lastTap;
  int _lastCount = -1;

  PauseMode get _mode => widget.mode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sound.setMuted(!widget.preferences.pauseSound);
    unawaited(NexKeepScreenOn.set(true));
    unawaited(_begin());
  }

  Future<void> _begin() async {
    // The sounds are made while the countdown is still to come; the first
    // tap of it waits for them, but no longer than a moment.
    await _sound
        .prepare(_mode)
        .timeout(const Duration(milliseconds: 1500), onTimeout: () {});
    if (!mounted) return;
    unawaited(_sound.countdown());
    _ticker.start();
  }

  /// Leaving the app pauses the session where it is. Frames stop in the
  /// background while the sound would go on, and coming back would jump the
  /// drawing ahead to catch up with a breath nobody took.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _stage == _Stage.breathing) {
      _togglePause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    unawaited(_sound.dispose());
    unawaited(NexKeepScreenOn.set(false));
    super.dispose();
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
          _restart(_Stage.breathing);
          unawaited(_sound.startBreathing());
          return;
        }
      case _Stage.breathing:
        final moment = pauseMomentAt(_mode, elapsed);
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

  /// Starts [stage] from its beginning.
  void _restart(_Stage stage) {
    _ticker.stop();
    _banked = Duration.zero;
    _elapsed = Duration.zero;
    _lastTap = null;
    setState(() => _stage = stage);
    _ticker.start();
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
        _ticker.stop();
        _banked = _elapsed;
        unawaited(_sound.pause());
        setState(() => _stage = _Stage.paused);
      case _Stage.paused:
        setState(() => _stage = _Stage.breathing);
        unawaited(_sound.resume());
        _ticker.start();
      case _Stage.countdown || _Stage.done:
        break;
    }
  }

  void _again() {
    _lastCount = -1;
    _restart(_Stage.countdown);
    unawaited(_sound.prepare(_mode).then((_) => _sound.countdown()));
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
    final moment = switch (_stage) {
      _Stage.breathing || _Stage.paused => pauseMomentAt(_mode, _elapsed),
      _ => null,
    };
    final fullness = moment?.fullness ?? 0;
    final left = switch (_stage) {
      _Stage.countdown => _mode.rounds,
      _Stage.done => 0,
      _ => _mode.rounds - moment!.round,
    };
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = (width - NexSpacing.lg * 2).clamp(0.0, 420.0);
    const white = Colors.white;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E12),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Center(
              child: SizedBox(
                width: cardWidth,
                child: AspectRatio(
                  aspectRatio: 0.82,
                  child: Semantics(
                    button:
                        _stage == _Stage.breathing || _stage == _Stage.paused,
                    label: _word(l10n, moment),
                    child: GestureDetector(
                      key: const ValueKey('pause-card'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _togglePause,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(NexRadius.xl * 2),
                        child: CustomPaint(
                          painter: PauseSkyPainter(
                            palette: PausePalette.of(_mode),
                            fullness: fullness,
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: AnimatedOpacity(
                                  opacity: _stage == _Stage.paused ? 0.4 : 1,
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
                                        fullness: _stage == _Stage.done
                                            ? 0.5
                                            : fullness,
                                        seconds: _elapsed.inMilliseconds / 1000,
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
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(color: white),
                                      ),
                                    ),
                                    Semantics(
                                      label: l10n.pauseBreathsLeft(
                                        nexDigits('$left', persian: persian),
                                      ),
                                      excludeSemantics: true,
                                      child: Text(
                                        nexDigits('$left', persian: persian),
                                        key: const ValueKey('pause-left'),
                                        style: theme.textTheme.titleMedium
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
                              Center(child: _centre(context, l10n, moment)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            _controls(context, l10n),
            const SizedBox(height: NexSpacing.xl),
          ],
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

  /// The words in the middle: the count, the breath, or the end.
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
    final Widget child = switch (_stage) {
      _Stage.countdown => Text(
        nexDigits('${3 - _elapsed.inSeconds.clamp(0, 2)}', persian: persian),
        key: const ValueKey('pause-count'),
        style: big,
      ),
      _Stage.breathing => Column(
        key: ValueKey(_word(l10n, moment)),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_word(l10n, moment), style: big),
          if (moment!.phase.step == PauseStep.holdFull ||
              moment.phase.step == PauseStep.holdEmpty)
            Text(
              nexDigits('${moment.secondsLeft}', persian: persian),
              style: small,
            ),
        ],
      ),
      _Stage.paused => Column(
        key: const ValueKey('paused'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.pausePaused, style: big),
          const SizedBox(height: NexSpacing.xs),
          Text(l10n.pauseTapToResume, style: small),
        ],
      ),
      _Stage.done => Column(
        key: const ValueKey('done'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.pauseDoneTitle, style: big),
          const SizedBox(height: NexSpacing.xs),
          Text(
            l10n.pauseDoneBody(
              nexDigits('${_mode.rounds}', persian: persian),
              pauseLength(_mode.sessionDuration, persian: persian),
            ),
            style: small,
          ),
        ],
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
          FilledButton.tonalIcon(
            key: const ValueKey('pause-again'),
            onPressed: _again,
            icon: const Icon(Icons.replay),
            label: Text(l10n.pauseAgain),
          ),
          const SizedBox(width: NexSpacing.md),
          round(
            key: const ValueKey('pause-close'),
            icon: Icons.close,
            tooltip: l10n.closeLabel,
            onPressed: () => Navigator.maybePop(context),
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
          onPressed: () => Navigator.maybePop(context),
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
