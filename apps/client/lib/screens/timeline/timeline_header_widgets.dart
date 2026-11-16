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
                  updatedAt: text?.trim().isNotEmpty == true ? updatedAt : null,
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
                        Tween(begin: const Offset(0, 0.025), end: Offset.zero),
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
            NexReveal(
              visible: !collapsed && lines.length > foldedLines,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in lines.skip(foldedLines)) _line(line),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The brief's heading: its mark and name, the last update, and the arrow
/// that says the card folds — with the number of lines folded away beside
/// it, so a folded brief never looks like a whole one.
///
/// The mark is a sparkle in a soft accent disc that turns and settles once
/// each time a new brief arrives — the one moment the card has news — and
/// stays still otherwise. The plain report gets a list mark instead: nothing
/// in it was written by a model, and the card should not claim otherwise.
class _BriefHeader extends StatelessWidget {
  const _BriefHeader({
    required this.title,
    required this.byModel,
    required this.token,
    required this.collapsed,
    required this.hidden,
    this.updatedAt,
    this.solarCalendar = false,
  });

  final String title;
  final bool byModel;
  final Object? token;
  final DateTime? updatedAt;
  final bool solarCalendar;
  final bool collapsed;

  /// Lines the folded card is not showing; none hides the count.
  final int hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final label = theme.textTheme.labelLarge?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    );
    final quiet = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w400,
    );
    final mark = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            scheme.primary.withValues(alpha: 0.2),
            scheme.tertiary.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: SizedBox.square(
        dimension: 24,
        child: Icon(
          byModel ? Icons.auto_awesome : Icons.checklist_rtl,
          size: 14,
          color: scheme.primary,
        ),
      ),
    );
    final at = updatedAt;
    return ExcludeSemantics(
      child: Row(
        children: [
          if (byModel)
            TweenAnimationBuilder<double>(
              key: ValueKey(token),
              tween: Tween(begin: 0, end: 1),
              duration: NexMotion.of(context, NexMotion.slow * 2),
              curve: Curves.easeOutBack,
              builder: (context, t, child) => Transform.rotate(
                angle: (1 - t) * -0.9,
                child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
              ),
              child: mark,
            )
          else
            mark,
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (at != null) ...[
            const SizedBox(width: NexSpacing.sm),
            Flexible(
              child: SummaryUpdatedTime(at: at, solarCalendar: solarCalendar),
            ),
          ],
          // What is folded away, said only while it is: open, the lines
          // themselves are the count.
          if (hidden > 0)
            AnimatedSwitcher(
              duration: NexMotion.of(context, NexMotion.standard),
              switchInCurve: NexMotion.curve,
              switchOutCurve: NexMotion.exitCurve,
              child: collapsed
                  ? Padding(
                      key: const ValueKey('brief-more'),
                      padding: const EdgeInsetsDirectional.only(
                        start: NexSpacing.sm,
                      ),
                      child: Text(
                        l10n.aiDaySummaryMore(hidden),
                        maxLines: 1,
                        style: quiet,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          const SizedBox(width: NexSpacing.xs),
          AnimatedRotation(
            // Folded, the arrow points down at what it would open; open, it
            // turns over to point back up.
            turns: collapsed ? 0 : 0.5,
            duration: NexMotion.of(context, NexMotion.standard),
            curve: NexMotion.curve,
            child: Icon(
              Icons.expand_more,
              key: const ValueKey('brief-fold-arrow'),
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the brief: its emoji in a column of its own, the words beside
/// it.
///
/// A hanging mark, the way a list is set. With the emoji inline, a line that
/// wrapped put its second row under the emoji rather than under the words,
/// and the width of each emoji — a phone and a stopwatch are not the same
/// width, and one drawn from the text font is narrower again — moved where
/// every line's words began. A column one emoji wide lines all of them up.
///
/// The line takes its own direction, so a Persian line in an English
/// interface puts its mark on the right.
class _BriefLine extends StatelessWidget {
  const _BriefLine(this.text, {this.folded = false, this.onOpen});

  final String text;

  /// The folded card shows each of its lines on one row.
  final bool folded;

  /// Opens the note this line was written from. Null for a line that is not
  /// about one note — a model's own sentence, a standing commitment — which
  /// leaves the tap to the card, as a fold.
  final VoidCallback? onOpen;

  /// The leading emoji, when the line starts with one: a first character that
  /// is neither a letter nor a digit, followed by a space.
  static (String, String)? split(String line) {
    final characters = line.characters;
    if (characters.length < 3) return null;
    final mark = characters.first;
    if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(mark)) return null;
    if (RegExp(r'^[\p{P}\s]', unicode: true).hasMatch(mark)) return null;
    final words = characters.skip(1).toString().trim();
    return words.isEmpty ? null : (mark, words);
  }

  @override
  Widget build(BuildContext context) {
    final direction = nexDirectionOf(text);
    final parts = split(text);
    final words = parts?.$2 ?? text;
    final paragraph = Text(
      words,
      maxLines: folded ? 1 : null,
      overflow: folded ? TextOverflow.ellipsis : TextOverflow.clip,
      textAlign: TextAlign.start,
      textDirection: direction,
    );
    final line = parts == null && onOpen == null
        ? paragraph
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (parts != null) ...[
                SizedBox(
                  // An emoji is about one and a quarter ems wide; the column
                  // grows with the text size so a large setting does not
                  // clip it.
                  width: MediaQuery.textScalerOf(context).scale(
                    (DefaultTextStyle.of(context).style.fontSize ?? 14) * 1.4,
                  ),
                  child: Text(parts.$1, textAlign: TextAlign.center),
                ),
                const SizedBox(width: NexSpacing.sm),
              ],
              Expanded(child: paragraph),
              // A line that leads to its note says so at its end, in the
              // direction it is read: the glyph turns round with the line.
              if (onOpen != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: NexSpacing.xs,
                    top: 2,
                  ),
                  child: Icon(
                    Icons.navigate_next_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          );
    final open = onOpen;
    // Room above and below each line, inside what a tap on it reaches: a
    // line that opens a note is a link in a paragraph, and the gap between
    // two of them belongs to one or the other rather than to neither.
    final padded = Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs - 1),
      child: Directionality(
        textDirection: direction ?? Directionality.of(context),
        child: line,
      ),
    );
    if (open == null) {
      return Semantics(label: text, excludeSemantics: true, child: padded);
    }
    return Semantics(
      label: text,
      link: true,
      excludeSemantics: true,
      onTap: open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          nexTick();
          open();
        },
        child: padded,
      ),
    );
  }
}
