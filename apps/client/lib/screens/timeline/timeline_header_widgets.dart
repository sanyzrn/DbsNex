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

/// The brief: the first card above the notes, in the slot the sponsor card
/// used to have.
///
/// It went through being a grey card with three buttons on it, then a bare
/// paragraph with a rule down its edge, and it is a card again — but not the
/// same one. What the first version got wrong was the chrome, not the shape:
/// a heading naming something already named, a sparkle, and three controls
/// for things that belong elsewhere. Those are all gone and they are what is
/// staying gone. What it has instead is a light travelling round its border,
/// which says a model wrote this without spending a row of the screen saying
/// it in words.
///
/// It does not take a card's fixed height. That rule exists so a sponsor
/// card cannot become an interruption; this one is the app reading the day
/// back, and how tall it is depends on how much there was to say.
///
/// Nothing here is a button any more, and none of the three that left was
/// lost:
///   * the recurring items are in the bottom bar, next to capture;
///   * refresh is the pull, which now has something to do — see the comment
///     on the timeline's `RefreshIndicator`;
///   * folding it away is still a tap, on the text itself.
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
  });

  final bool loading;
  final String? text;
  final String emptyLabel;
  final bool collapsed;
  final String semanticLabel;
  final String toggleTooltip;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      button: true,
      // What the tap does, which used to be a tooltip on a chevron that no
      // longer exists. A screen reader is the one place the affordance still
      // has to be spelled out: sighted readers get a paragraph that folds,
      // and there is nothing about a paragraph that needs explaining.
      hint: toggleTooltip,
      child: NexTappable(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(NexRadius.lg)),
        ),
        onTap: onToggle,
        child: Padding(
          // A card's inset now that this is a card. It used to be a
          // paragraph loose on the page, where the only thing keeping it off
          // the edge was the header's own margin.
          padding: const EdgeInsets.all(NexSpacing.cardInset),
          child: NexAnimatedSize(
            // No rule down the edge any more, and still no heading. The
            // light going round the card says the same thing the rule did —
            // a model wrote this — and two marks for one fact is one mark
            // too many.
            child: AnimatedSwitcher(
              duration: NexMotion.of(context, NexMotion.enter),
              reverseDuration: NexMotion.of(context, NexMotion.exit),
              switchInCurve: NexMotion.curve,
              switchOutCurve: NexMotion.exitCurve,
              layoutBuilder: (current, previous) => Stack(
                alignment: AlignmentDirectional.topStart,
                children: [
                  for (final child in previous)
                    ExcludeSemantics(child: IgnorePointer(child: child)),
                  if (current != null) current,
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
                child: _body(context, theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The recap's opening sentence, for the folded state.
  Widget _body(BuildContext context, ThemeData theme) {
    final value = text;
    final base = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final body = base.copyWith(height: 1.45);
    if (value == null) {
      // No skeleton bars. They were the last thing in here shaped like a
      // box, and two grey rectangles at the top of a first launch could be
      // anything; the sentence that says there is nothing to summarise yet
      // is the same sentence either way, so it is simply dimmed while the
      // first one is being written.
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
    final lines = [
      for (final line in value.trim().split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.isEmpty) lines.add(value.trim());
    final muted = body.copyWith(color: theme.colorScheme.onSurfaceVariant);
    // A refresh keeps the last successful text fully readable.
    return AnimatedOpacity(
      opacity: 1,
      duration: NexMotion.of(context, NexMotion.slow),
      curve: NexMotion.curve,
      child: Column(
        // Min, because this sits in an [IntrinsicHeight] row: a column that
        // asks for all the height there is has no intrinsic height to give.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Every line the same widget, the same type and the same gap
          // (2.1.7). The first one used to be a plain `Text` with a wider gap
          // under it and the rest one paragraph below, and the first line of
          // the brief read as a heading over a list it is simply the top of.
          AnimatedDefaultTextStyle(
            duration: NexMotion.of(context, NexMotion.slow),
            curve: NexMotion.curve,
            style: collapsed ? muted : body,
            child: _BriefLine(lines.first, folded: collapsed),
          ),
          NexReveal(
            visible: !collapsed && lines.length > 1,
            child: DefaultTextStyle.merge(
              style: body,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Per line, because the recap is written in the language
                  // of the notes and the notes are the one place in this app
                  // most likely to be in both at once — each line takes its
                  // own direction.
                  //
                  // Not selectable, unlike the note body in the detail
                  // sheet. The whole card is one button — a tap anywhere on
                  // it folds the brief away — and a `SelectionArea` would
                  // claim that tap for clearing a selection.
                  for (final line in lines.skip(1)) ...[
                    const SizedBox(height: NexSpacing.xs + 2),
                    _BriefLine(line),
                  ],
                ],
              ),
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
  const _BriefLine(this.text, {this.folded = false});

  final String text;

  /// The folded card shows the first line on one row.
  final bool folded;

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
    final line = parts == null
        ? paragraph
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                // An emoji is about one and a quarter ems wide; the column
                // grows with the text size so a large setting does not clip
                // it.
                width: MediaQuery.textScalerOf(context).scale(
                  (DefaultTextStyle.of(context).style.fontSize ?? 14) * 1.4,
                ),
                child: Text(parts.$1, textAlign: TextAlign.center),
              ),
              const SizedBox(width: NexSpacing.sm),
              Expanded(child: paragraph),
            ],
          );
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Directionality(
        textDirection: direction ?? Directionality.of(context),
        child: line,
      ),
    );
  }
}
