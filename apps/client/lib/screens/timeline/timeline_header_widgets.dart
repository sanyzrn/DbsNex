part of '../timeline_screen.dart';

/// The app's own mark, in the corner the app bar used to spend on a title.
///
/// Bare, on no ground of its own. It had a rounded tile behind it to match the
/// footprint of the two icon buttons opposite — but those are buttons and
/// this is not, so the tile was claiming an affordance the mark does not have,
/// and it read as a fourth button that does nothing. A touch on it plays its
/// movement, a small thing to find rather than a control.
///
/// The "nex" wordmark, drawn from the brand's own vectors ([NexLogotype])
/// rather than a picture, so it stays crisp and follows light and dark.
/// [_height] puts its letters on the same optical line as the icons across
/// from it.
class _WordmarkTile extends StatelessWidget {
  const _WordmarkTile();

  static const _height = 16.0;

  @override
  Widget build(BuildContext context) =>
      const NexLivingLogotype(height: _height);
}

/// The day's header settling back as the notes come up over it.
///
/// As the list moves, the date and the greeting fall behind at a third of
/// its pace and fade, inside their own box — so the header reads as the
/// ground the notes travel over rather than as the first row of them, and it
/// is gone before it could sit under anything. Scroll-linked, never timed:
/// it is exactly as far along as the finger is, and still when the finger
/// is. With animations off the header simply scrolls.
///
/// It listens to the list rather than rebuilding with it. A scroll controller
/// speaks on every frame of a scroll, for as long as the scroll lasts; this
/// only has anything to do over the first [_over] pixels, and holds one
/// value — rebuilding nothing — for all the rest (the timeline's budget is
/// that a steady scroll rebuilds no widget at all).
class _HeroRecede extends StatefulWidget {
  const _HeroRecede({required this.scroll, required this.child});

  final ScrollController scroll;
  final Widget child;

  /// How far the list has to move for the header to have faded out.
  static const _over = 160.0;

  @override
  State<_HeroRecede> createState() => _HeroRecedeState();
}

class _HeroRecedeState extends State<_HeroRecede> {
  /// How far the header has receded, from 0 to [_HeroRecede._over]. Only
  /// tells its listeners when it changes, which past the fade it never does.
  final _travel = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_moved);
  }

  @override
  void didUpdateWidget(_HeroRecede old) {
    super.didUpdateWidget(old);
    if (old.scroll == widget.scroll) return;
    old.scroll.removeListener(_moved);
    widget.scroll.addListener(_moved);
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_moved);
    _travel.dispose();
    super.dispose();
  }

  void _moved() {
    final scroll = widget.scroll;
    // The first position, not `offset`: while one tree replaces another the
    // controller briefly holds two, and `offset` asserts on that.
    final offset = scroll.hasClients ? scroll.positions.first.pixels : 0.0;
    // At rest, and while a pull stretches the list the other way, zero.
    _travel.value = offset.clamp(0.0, _HeroRecede._over);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return ValueListenableBuilder<double>(
      valueListenable: _travel,
      child: widget.child,
      builder: (context, travel, child) {
        // At rest the header is itself: no layer, no clip.
        if (travel <= 0) return child!;
        final t = travel / _HeroRecede._over;
        return ClipRect(
          child: Opacity(
            opacity: 1 - NexMotion.exitCurve.transform(t),
            child: Transform.translate(
              offset: Offset(0, travel * 0.3),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// "Good evening, Saeed ☀️" — the text and its animated mark on one line.
class _GreetingLine extends StatelessWidget {
  const _GreetingLine({
    required this.text,
    required this.style,
    this.loading = false,
  });

  final String text;
  final TextStyle? style;

  /// The generated half is on its way. The greeting is already there, so the
  /// line dims rather than disappearing — a refresh should read as the words
  /// being replaced, not as them being taken away and given back.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty && !loading) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: NexMotion.of(context, NexMotion.standard),
      child: Opacity(
        key: ValueKey(text),
        opacity: 1,
        // A Text, not a Row of one. The Row existed to place a mark at the
        // trailing end of the words; with the mark gone it was a layout
        // holding a single child and deciding nothing.
        // The full width, so the start alignment below has a line to be at
        // the start of; sized to its words, the switcher centred it.
        child: SizedBox(
          width: double.infinity,
          child: Text(
            text,
            style: style,
            // The greeting is written in the language of the user's name, which
            // is not necessarily the interface's, and a Persian sentence laid
            // out left-to-right puts its full stop at the wrong end.
            textDirection: nexDirectionOf(text),
            // Two, because the generated half joined on the end of a greeting is
            // regularly longer than one line and cutting it mid-phrase reads as
            // a bug.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            // At the interface's start, under the date — not centred, and not
            // at the start of the *name's* language: a Persian name in an
            // English interface would otherwise put the line on the far side
            // of the date it belongs to.
            textAlign: Directionality.of(context) == TextDirection.rtl
                ? TextAlign.right
                : TextAlign.left,
          ),
        ),
      ),
    );
  }
}

/// Today, named: the weekday and the date in the reader's calendar, over the
/// greeting.
///
/// The header was one centred line, and the one thing it could have said for
/// free — what day it is, in the calendar the reader actually uses — it did
/// not. The dot is the accent's, the same mark the onboarding's miniature
/// timeline puts beside "Today".
class _TodayLine extends StatelessWidget {
  const _TodayLine({required this.solar});

  final bool solar;

  static const _faDays = [
    'دوشنبه',
    'سه‌شنبه',
    'چهارشنبه',
    'پنج‌شنبه',
    'جمعه',
    'شنبه',
    'یکشنبه',
  ];
  static const _enDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final now = DateTime.now();
    final text = persian
        ? '${_faDays[now.weekday - 1]}، ${nexReadableDate(now, solar: solar, persian: true)}'
        : '${_enDays[now.weekday - 1]}, ${nexReadableDate(now, solar: solar, persian: false)}';
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: NexSpacing.sm),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// The brief: the app reading the day back, under the greeting it follows on
/// from.
///
/// It went through being a grey card with three buttons on it, a bare
/// paragraph with a rule down its edge, and a card in the notes' own slot.
/// Since 2.8.0 it is part of the day's header: a surface in the accent's own
/// wash rather than a note's, so it is never taken for one of the reader's
/// notes, and small by default — its heading and its first two lines, with
/// the number of lines folded away beside the arrow that opens them.
///
/// Three things about it are deliberate:
///   * the whole card folds and opens, on a tap anywhere that is not a line
///     leading somewhere, and the fold is remembered;
///   * a line the app wrote from a note opens that note — the brief used to
///     be something to read and then go looking for;
///   * nothing here refreshes it. That is the pull, and it is the pull's
///     only job.
class _AiDaySummaryPanel extends StatelessWidget {
  const _AiDaySummaryPanel({
    super.key,
    required this.loading,
    required this.text,
    required this.emptyLabel,
    required this.collapsed,
    required this.semanticLabel,
    required this.toggleTooltip,
    required this.onToggle,
    required this.title,
    required this.byModel,
    this.updatedAt,
    this.solarCalendar = false,
    this.noteFor,
    this.onOpenNote,
  });

  /// How many lines the folded card still shows.
  static const foldedLines = 2;

  /// The card's name, over the brief.
  final String title;

  /// Beside the name while a model writes the brief; the plain report is
  /// Nex's own arithmetic and does not wear it.
  final bool byModel;
  final DateTime? updatedAt;
  final bool solarCalendar;

  final bool loading;
  final String? text;
  final String emptyLabel;
  final bool collapsed;
  final String semanticLabel;
  final String toggleTooltip;
  final VoidCallback onToggle;

  /// The note a line was written from, when the app wrote it from one.
  final String? Function(String line)? noteFor;
  final ValueChanged<String>? onOpenNote;

  List<String> get _lines {
    final value = text;
    if (value == null) return const [];
    final lines = [
      for (final line in value.trim().split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.isEmpty) lines.add(value.trim());
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = _lines;
    final hidden = lines.length - foldedLines;
    return Semantics(
      container: true,
      label: semanticLabel,
      button: true,
      // What the tap does. A screen reader is the one place the affordance
      // has to be spelled out in words; the arrow says it to the eye.
      hint: toggleTooltip,
      // The lines that lead to a note are links of their own inside it.
      explicitChildNodes: true,
      child: NexTappable(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(NexRadius.lg)),
        ),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.cardInset,
            vertical: NexSpacing.sm + NexSpacing.xs,
          ),
          // Its bottom edge is where folding lines go under (2.8.2).
          child: ClipRect(
            clipper: const _BottomEdge(),
            child: NexAnimatedSize(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BriefHeader(
                    title: title,
                    byModel: byModel,
                    // A new brief makes the mark twinkle once.
                    token: text,
                    updatedAt: text?.trim().isNotEmpty == true
                        ? updatedAt
                        : null,
                    solarCalendar: solarCalendar,
                    collapsed: collapsed,
                    hidden: hidden > 0 ? hidden : 0,
                  ),
                  const SizedBox(height: NexSpacing.xs),
                  AnimatedSwitcher(
                    duration: NexMotion.of(context, NexMotion.enter),
                    reverseDuration: NexMotion.of(context, NexMotion.exit),
                    switchInCurve: NexMotion.curve,
                    switchOutCurve: NexMotion.exitCurve,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: AlignmentDirectional.topStart,
                      children: [
                        for (final child in previous)
                          ExcludeSemantics(child: IgnorePointer(child: child)),
                        ?current,
                      ],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: animation.drive(
                          Tween(
                            begin: const Offset(0, 0.025),
                            end: Offset.zero,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(text),
                      child: _body(context, theme, lines),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String line, {bool folded = false}) {
    final id = noteFor?.call(line);
    final open = onOpenNote;
    return _BriefLine(
      line,
      folded: folded,
      onOpen: id == null || open == null ? null : () => open(id),
    );
  }

  Widget _body(BuildContext context, ThemeData theme, List<String> lines) {
    final base = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final body = base.copyWith(height: 1.45);
    if (text == null || lines.isEmpty) {
      // No skeleton bars. Two grey rectangles at the top of a first launch
      // could be anything; the sentence that says there is nothing to
      // summarise yet is the same sentence either way, so it is simply
      // dimmed while the first one is being written.
      return AnimatedOpacity(
        opacity: loading ? 0.5 : 1,
        duration: NexMotion.of(context, NexMotion.slow),
        curve: NexMotion.curve,
        child: Text(
          emptyLabel,
          style: body.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.start,
          textDirection: nexDirectionOf(emptyLabel),
        ),
      );
    }
    // Every line the same widget, the same type and the same gap (2.1.6):
    // the first one is simply the top of the list, not a heading over it.
    // Per line, because the brief is written in the language of the notes
    // and the notes are the one place most likely to be in both at once —
    // each line takes its own direction.
    //
    // Not selectable, unlike the note body in the detail sheet: the card is
    // one button, and a `SelectionArea` would claim its tap for clearing a
    // selection.
    //
    // A refresh keeps the last successful text fully readable: the opacity
    // is the same widget the empty state dims, held at one.
    return AnimatedOpacity(
      opacity: 1,
      duration: NexMotion.of(context, NexMotion.slow),
      curve: NexMotion.curve,
      child: DefaultTextStyle.merge(
        style: body,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in lines.take(foldedLines))
              _line(line, folded: collapsed),
            // One size animation, the card's own (2.8.1). These lines used
            // to grow inside a reveal of their own while the card animated
            // its size round them, so the card chased a height that changed
            // every frame and the opening stuttered. Now the card opens once
            // and its lines arrive after one another into the room it makes.
            // Folding, they do not leave on the frame of the tap (2.8.2):
            // they fade while the card closes over them.
            _FoldingLines(
              open: !collapsed,
              lines: [
                for (final (i, line) in lines.skip(foldedLines).indexed)
                  _ArrivingLine(index: i, child: _line(line)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
