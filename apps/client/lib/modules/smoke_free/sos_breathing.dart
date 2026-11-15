import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';

/// A voluntary slow-breathing cue: four counts in and six out until
/// stopped. The circle grows and shrinks with the breath; with reduced
/// motion only the words and the count change.
class SosBreathing extends StatefulWidget {
  const SosBreathing({super.key});

  @override
  State<SosBreathing> createState() => _BreathingState();
}

class _BreathingState extends State<SosBreathing>
    with SingleTickerProviderStateMixin {
  static const _in = 4, _out = 6, _cycle = _in + _out;
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
    final out = seconds - _in;
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
                ? nexDigits('${phase.count}', persian: true)
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
