part of '../timeline_screen.dart';

/// The app's own mark, in the corner the app bar used to spend on a title.
///
/// Bare, on no ground of its own. It had a rounded tile behind it to match the
/// footprint of the two icon buttons opposite — but those are tap targets and
/// this is not, so the tile was claiming an affordance the mark does not have,
/// and it read as a fourth button that does nothing.
///
/// The "nex" wordmark, drawn from the brand's own vectors ([NexLogotype])
/// rather than a picture, so it stays crisp and follows light and dark.
/// [_height] puts its letters on the same optical line as the icons across
/// from it.
class _WordmarkTile extends StatelessWidget {
  const _WordmarkTile();

  static const _height = 20.0;

  @override
  Widget build(BuildContext context) => const NexLogotype(height: _height);
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
      duration: NexMotion.standard,
      child: Opacity(
        key: ValueKey(text),
        opacity: loading ? 0.45 : 1,
        // A Text, not a Row of one. The Row existed to place a mark at the
        // trailing end of the words; with the mark gone it was a layout
        // holding a single child and deciding nothing.
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
          textAlign: TextAlign.center,
        ),
      ),
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

  /// What the first line is set at, relative to the rest.
  ///
  /// A lede, not a heading: the same face and the same weight, one step up in
  /// size. Anything more and it becomes the title this deliberately does not
  /// have.
  static const _ledeScale = 1.12;

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
      child: GestureDetector(
        // Not a [NexTappable]: its pressed fill is drawn on the shape it is
        // given, and the shape here belongs to the glass surface outside it,
        // which would end up with a grey wash over its own material.
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Padding(
          // A card's inset now that this is a card. It used to be a
          // paragraph loose on the page, where the only thing keeping it off
          // the edge was the header's own margin.
          padding: const EdgeInsets.all(NexSpacing.cardInset),
          child: AnimatedSize(
            duration: NexMotion.slow,
            curve: NexMotion.curve,
            alignment: Alignment.topCenter,
            // No rule down the edge any more, and still no heading. The
            // light going round the card says the same thing the rule did —
            // a model wrote this — and two marks for one fact is one mark
            // too many.
            child: collapsed
                ? _CollapsedRecap(label: _firstLine ?? emptyLabel)
                : _body(theme),
          ),
        ),
      ),
    );
  }

  /// The recap's opening sentence, for the folded state.
  String? get _firstLine {
    final value = text?.trim();
    if (value == null || value.isEmpty) return null;
    final end = value.indexOf('\n');
    return end == -1 ? value : value.substring(0, end);
  }

  Widget _body(ThemeData theme) {
    final value = text;
    // Defaulted rather than carried around as a nullable: the lede's size is
    // this one's times a factor, and `base?.copyWith(base.fontSize ...)` does
    // not compile — a `?.` does not promote its own receiver inside its
    // arguments.
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
        duration: NexMotion.slow,
        curve: NexMotion.curve,
        child: Text(
          emptyLabel,
          style: body.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.start,
          textDirection: nexDirectionOf(emptyLabel),
        ),
      );
    }
    final lines = value.trim().split('\n');
    final lede = lines.first;
    final rest = lines.skip(1).join('\n').trim();
    // Cross-faded rather than dimmed and left in place: a rewrite replaces
    // the text, and a paragraph that goes translucent and comes back with
    // different words in it is the honest picture of that.
    return AnimatedOpacity(
      opacity: loading ? 0.45 : 1,
      duration: NexMotion.slow,
      curve: NexMotion.curve,
      child: Column(
        // Min, because this sits in an [IntrinsicHeight] row: a column that
        // asks for all the height there is has no intrinsic height to give.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            lede,
            style: body.copyWith(fontSize: (base.fontSize ?? 14) * _ledeScale),
            textDirection: nexDirectionOf(lede),
            textAlign: nexDirectionOf(lede) == TextDirection.rtl
                ? TextAlign.right
                : TextAlign.left,
          ),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: NexSpacing.sm),
            // Per line, because the recap is written in the language of the
            // notes and the notes are the one place in this app most likely
            // to be in both at once — see [NexTextSurface].
            //
            // Not selectable, unlike the note body in the detail sheet. The
            // whole card is one button — a tap anywhere on it folds the brief
            // away — and a `SelectionArea` would claim that tap for clearing
            // a selection. A paragraph you can select inside a card that
            // stops responding is the worse of the two trades.
            NexTextSurface(rest, style: body),
          ],
        ],
      ),
    );
  }
}

/// The recap folded away: one line, truncated, with no rule beside it.
///
/// The rule stays behind on purpose. Open, it marks a block of generated
/// prose; closed, there is no block, and a two-pixel accent stripe next to a
/// single grey line reads as a status colour on a row — which is a different
/// claim than the one it is there to make.
class _CollapsedRecap extends StatelessWidget {
  const _CollapsedRecap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      textDirection: nexDirectionOf(label),
    );
  }
}
