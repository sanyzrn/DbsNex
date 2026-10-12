part of '../onboarding_screen.dart';

// The two pictures drawn from the app's own parts: its cards and its search.

// ---------------------------------------------------------------------------
// 2. Capture: notes land on the timeline, and nothing asks to be saved.
// ---------------------------------------------------------------------------

class _CaptureArt extends _Art {
  const _CaptureArt({required super.play});

  @override
  Duration get duration => const Duration(milliseconds: 2600);

  @override
  State<_CaptureArt> createState() => _CaptureArtState();
}

class _CaptureArtState extends _ArtState<_CaptureArt> {
  static const _arrivals = [0.08, 0.38, 0.68];
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final cards = [
      _MiniCard(
        icon: Icons.notes,
        hue: NexHue.sky,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_Bar(0.9, strong: true), SizedBox(height: 7), _Bar(0.6)],
        ),
      ),
      _MiniCard(
        icon: Icons.mic_none,
        hue: NexHue.violet,
        child: _Wave(color: NexHue.violet.of(theme.brightness)),
      ),
      _MiniCard(
        icon: Icons.checklist,
        hue: NexHue.teal,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Tick(done: true, color: NexHue.teal.of(theme.brightness)),
            const SizedBox(height: 6),
            _Tick(done: false, color: NexHue.teal.of(theme.brightness)),
          ],
        ),
      ),
    ];
    return _Panel(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final arrived = [
            for (final a in _arrivals) span(a, a + 0.22, Curves.easeOutBack),
          ];
          final landed = [for (final a in _arrivals) span(a, a + 0.22)];
          return Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Text(
                    l10n.timelineGroupToday,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NexSpacing.sm),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (var i = 0; i < cards.length; i++)
                      if (landed[i] > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          // Newest on top: every card that lands after this
                          // one pushes it a slot further down.
                          top:
                              (_MiniCard.height + _gap) *
                                  [
                                    for (var j = i + 1; j < cards.length; j++)
                                      landed[j],
                                  ].fold(0.0, (a, b) => a + b) -
                              (1 - arrived[i]) * 24,
                          child: Opacity(opacity: landed[i], child: cards[i]),
                        ),
                  ],
                ),
              ),
              _CaptureButton(
                pulses: [for (final a in _arrivals) span(a - 0.06, a + 0.2)],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The capture button at the foot of the miniature, with a ring leaving it
/// as each note lands.
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.pulses});

  final List<double> pulses;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (final p in pulses)
            if (p > 0 && p < 1)
              Container(
                width: 44 + 26 * p,
                height: 44 + 26 * p,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.5 * (1 - p)),
                    width: 2,
                  ),
                ),
              ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(NexRadius.md + 2),
            ),
            child: Icon(Icons.add, color: scheme.onPrimary),
          ),
        ],
      ),
    );
  }
}

/// A voice note's recording, as bars.
class _Wave extends StatelessWidget {
  const _Wave({required this.color});

  final Color color;

  static const _levels = [
    .35, .6, .9, .5, .75, 1.0, .55, .3, .65, .85, .45, .7, .4, .6, .25, .5, //
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final level in _levels) ...[
          Container(
            width: 3,
            height: 4 + 22 * level,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 3),
        ],
        const Spacer(),
        Text(
          '0:12',
          textDirection: TextDirection.ltr,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

/// A checklist line in a miniature: a box, ticked or not, and its "words".
class _Tick extends StatelessWidget {
  const _Tick({required this.done, required this.color});

  final bool done;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: done ? color : null,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color, width: 1.5),
          ),
          child: done
              ? Icon(
                  Icons.check,
                  size: 9,
                  color: Theme.of(context).colorScheme.surface,
                )
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(child: _Bar(done ? 0.5 : 0.7, strong: !done)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Find: a search that reads Persian the way it is typed.
// ---------------------------------------------------------------------------

/// The search field types a word — in Persian, with the Arabic letters a
/// phone keyboard so often gives — and the notes holding it come up with the
/// word lit, written the Persian way. The point is made by what matches, not
/// by a sentence about it.
class _FindArt extends _Art {
  const _FindArt({required super.play});

  @override
  Duration get duration => const Duration(milliseconds: 2800);

  @override
  State<_FindArt> createState() => _FindArtState();
}

class _FindArtState extends _ArtState<_FindArt> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final query = l10n.onboardingFindQuery;
    final violet = NexHue.violet.of(theme.brightness);
    return _Panel(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final typed = (span(0.04, 0.34, Curves.linear) * query.length)
              .round();
          final first = span(0.38, 0.6);
          final second = span(0.48, 0.7);
          final ai = span(0.78, 1);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(NexRadius.pill),
                  border: Border.all(color: scheme.primary, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: scheme.primary),
                    const SizedBox(width: NexSpacing.sm),
                    Text(
                      query.substring(0, typed),
                      style: theme.textTheme.bodyLarge,
                    ),
                    // The caret, while there is still typing to do.
                    if (typed < query.length || controller.value < 0.36)
                      Container(
                        width: 2,
                        height: 20,
                        margin: const EdgeInsetsDirectional.only(start: 2),
                        color: scheme.primary,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: NexSpacing.md),
              for (final (text, shown) in [
                (l10n.onboardingFindResultA, first),
                (l10n.onboardingFindResultB, second),
              ]) ...[
                Opacity(
                  opacity: shown,
                  child: Transform.translate(
                    offset: Offset(0, (1 - shown) * 12),
                    child: _MiniCard(
                      icon: Icons.notes,
                      hue: NexHue.sky,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _Lit(
                          text: text,
                          match: l10n.onboardingFindMatch,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: NexSpacing.sm),
              ],
              const Spacer(),
              Opacity(
                opacity: ai,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(NexRadius.pill),
                      border: Border.all(color: violet.withValues(alpha: 0.5)),
                      color: violet.withValues(alpha: 0.08),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NexSpacing.md - 4,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 15,
                            color: violet,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              l10n.onboardingFindAi,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A result's words with the match lit, the way the app's own search lights
/// it.
class _Lit extends StatelessWidget {
  const _Lit({required this.text, required this.match});

  final String text;
  final String match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium;
    final lit = base?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onPrimaryContainer,
      backgroundColor: theme.colorScheme.primaryContainer,
    );
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final needle = match.toLowerCase();
    var from = 0;
    while (needle.isNotEmpty) {
      final at = lower.indexOf(needle, from);
      if (at < 0) break;
      if (at > from) spans.add(TextSpan(text: text.substring(from, at)));
      spans.add(
        TextSpan(text: text.substring(at, at + needle.length), style: lit),
      );
      from = at + needle.length;
    }
    if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textDirection: nexDirectionOf(text),
    );
  }
}
