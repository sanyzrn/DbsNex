import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'craving_sheet.dart';
import 'module.dart';
import 'quit_model.dart';

/// The help button: three ways to get through a craving — breathe, wait it
/// out, do something else — with the person's own reason one glance away.
/// Nothing is recorded unless they choose to log the craving.
Future<void> showSosSheet(
  BuildContext context,
  NexModuleStore store,
  QuitAttempt attempt,
) => nexShowSheet<void>(
  context: context,
  builder: (sheet) => _SosSheet(store: store, attempt: attempt),
);

enum _Mode { breathe, wait, distract }

class _SosSheet extends StatefulWidget {
  const _SosSheet({required this.store, required this.attempt});

  final NexModuleStore store;
  final QuitAttempt attempt;

  @override
  State<_SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<_SosSheet> {
  _Mode _mode = _Mode.breathe;

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final why = widget.attempt.why.trim();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(NexSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings(context, 'sosTitle'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.xs),
            Text(
              strings(context, 'sosIntro'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (why.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.md),
              NexPanel(
                key: const ValueKey('sos-why'),
                title: strings(context, 'remember'),
                icon: Icons.favorite_border,
                child: NexTextDirection(
                  text: why,
                  child: Text(why, style: theme.textTheme.bodyLarge),
                ),
              ),
            ],
            const SizedBox(height: NexSpacing.md),
            SegmentedButton<_Mode>(
              key: const ValueKey('sos-modes'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _Mode.breathe,
                  label: Text(strings(context, 'tabBreathe')),
                ),
                ButtonSegment(
                  value: _Mode.wait,
                  label: Text(strings(context, 'tabWait')),
                ),
                ButtonSegment(
                  value: _Mode.distract,
                  label: Text(strings(context, 'tabDistract')),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: NexSpacing.md),
            switch (_mode) {
              _Mode.breathe => const _Breathing(),
              _Mode.wait => const _WaitTimer(),
              _Mode.distract => const _Tips(),
            },
            const SizedBox(height: NexSpacing.md),
            OutlinedButton.icon(
              key: const ValueKey('sos-log'),
              icon: const Icon(Icons.edit_note_outlined),
              label: Text(strings(context, 'logIt')),
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                unawaited(
                  showCravingSheet(
                    navigator.context,
                    widget.store,
                    habit: widget.attempt.key,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 4-7-8: four counts in, seven held, eight out, over and over until
/// stopped. The circle grows and shrinks with the breath; with reduced
/// motion only the words and the count change.
class _Breathing extends StatefulWidget {
  const _Breathing();

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  static const _in = 4, _hold = 7, _out = 8, _cycle = _in + _hold + _out;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _cycle),
  );
  bool _running = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _running = !_running);
    if (_running) {
      unawaited(_controller.repeat());
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  ({String key, int count, double scale}) _phase(double t) {
    final seconds = t * _cycle;
    if (seconds < _in) {
      return (
        key: 'breatheIn',
        count: _in - seconds.floor(),
        scale: 0.55 + 0.45 * (seconds / _in),
      );
    }
    if (seconds < _in + _hold) {
      return (
        key: 'breatheHold',
        count: (_in + _hold) - seconds.floor(),
        scale: 1,
      );
    }
    final out = seconds - _in - _hold;
    return (
      key: 'breatheOut',
      count: _cycle - seconds.floor(),
      scale: 1 - 0.45 * (out / _out),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final persian = NexModuleStrings.persian(context);
    return Column(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final phase = _phase(_controller.value);
            final count = persian
                ? '${phase.count}'.replaceAllMapped(
                    RegExp('[0-9]'),
                    (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
                  )
                : '${phase.count}';
            return Semantics(
              liveRegion: true,
              label: _running
                  ? '${strings(context, phase.key)} $count'
                  : strings(context, 'tabBreathe'),
              child: SizedBox(
                height: 180,
                child: Center(
                  child: Transform.scale(
                    scale: still || !_running ? 0.8 : phase.scale,
                    child: Container(
                      width: 160,
                      height: 160,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.18,
                        ),
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      child: _running
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  strings(context, phase.key),
                                  style: theme.textTheme.titleMedium,
                                ),
                                Text(
                                  count,
                                  key: const ValueKey('sos-breath-count'),
                                  style: theme.textTheme.headlineMedium,
                                ),
                              ],
                            )
                          : const Icon(Icons.air, size: 40),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: NexSpacing.sm),
        Text(
          strings(context, 'breatheNote'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        FilledButton(
          key: const ValueKey('sos-breath-toggle'),
          onPressed: _toggle,
          child: Text(
            strings(context, _running ? 'breatheStop' : 'breatheStart'),
          ),
        ),
      ],
    );
  }
}

/// "Urge surfing": a ten-minute clock to let a craving crest and fall.
class _WaitTimer extends StatefulWidget {
  const _WaitTimer();

  @override
  State<_WaitTimer> createState() => _WaitTimerState();
}

class _WaitTimerState extends State<_WaitTimer> {
  static const _total = 10 * 60;
  Timer? _timer;
  int _left = _total;
  bool _started = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    setState(() {
      _started = true;
      _left = _total;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final done = _started && _left <= 0;
    final time =
        '${(_left ~/ 60).toString().padLeft(2, '0')}:'
        '${(_left % 60).toString().padLeft(2, '0')}';
    final shown = persian
        ? time.replaceAllMapped(
            RegExp('[0-9]'),
            (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
          )
        : time;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (done)
          Text(
            strings(context, 'waitDone'),
            key: const ValueKey('sos-wait-done'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          )
        else if (_started)
          Text(
            strings(context, 'waitLeft', {'time': shown}),
            key: const ValueKey('sos-wait-left'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          )
        else
          Text(
            strings(context, 'waitHint'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        const SizedBox(height: NexSpacing.md),
        if (_started && !done)
          LinearProgressIndicator(value: 1 - _left / _total),
        const SizedBox(height: NexSpacing.sm),
        FilledButton(
          key: const ValueKey('sos-wait-start'),
          onPressed: _start,
          child: Text(strings(context, _started ? 'waitReset' : 'waitStart')),
        ),
      ],
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    return Column(
      children: [
        for (final (i, icon) in const [
          Icons.water_drop_outlined,
          Icons.directions_walk,
          Icons.chat_bubble_outline,
          Icons.face_outlined,
          Icons.back_hand_outlined,
        ].indexed)
          ListTile(
            leading: Icon(icon),
            title: Text(strings(context, 'tip${i + 1}')),
          ),
      ],
    );
  }
}
