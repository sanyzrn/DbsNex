part of '../ai_chat_sheet.dart';

/// A stable spoken status with a small, quiet animation while a reply arrives.
/// Its 1.5s repeating cadence is independent of enter/exit transition timing.
class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator();

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) || !TickerMode.of(context)) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = AppLocalizations.of(context).chatThinking;
    return Semantics(
      key: const ValueKey('assistant-thinking'),
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: NexSurface(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.md,
              vertical: NexSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: NexSpacing.sm),
                Flexible(child: Text(label, style: theme.textTheme.bodyMedium)),
                const SizedBox(width: NexSpacing.sm),
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var dot = 0; dot < 3; dot++)
                          Transform.translate(
                            offset: Offset(0, -2 * _wave(dot)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Opacity(
                                opacity: 0.35 + 0.65 * _wave(dot),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme.colorScheme.primary,
                                  ),
                                  child: const SizedBox(width: 5, height: 5),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _wave(int dot) =>
      (math.sin((_pulse.value - dot * 0.18) * math.pi * 2) + 1) / 2;
}
