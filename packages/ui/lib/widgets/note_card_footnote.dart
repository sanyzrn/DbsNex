part of 'note_card.dart';

extension on _CardBody {
  /// The note's words, and — only when there are any — the marks of what it
  /// carries besides: when it will remind, how many more files it holds.
  ///
  /// The marks sit where the words end, on their last line, the way a
  /// message's time sits at the end of its last line in a chat: a note on
  /// one short line carries them on that same line, and a note that fills
  /// its lines fades out just before them. So they cost the card no line.
  ///
  /// Three places came before. A column at the end of the row, one pill
  /// above the other, took its width from every line of the note beside it.
  /// A line of their own under the words (1.99.93) did not fit the card's
  /// one height and was cut off on a compact card. That line taking the
  /// place of the words' last line (1.99.94) fitted, and cost every such
  /// card a line of its note.
  ///
  /// A checklist carries them at the end of its first row instead: its last
  /// row ends in "+3" when there are more items, and its rows are short.
  /// A card showing its whole note grows instead, so there they keep a line
  /// of their own under it, and no word is faded.
  Widget _withFootnote(BuildContext context) {
    final due = showDue ? note.dueAt : null;
    final attached = note.attachmentCount > 0;
    final marked = due != null || attached;
    final preview =
        previewOverride ??
        _Preview(
          note: note,
          expanded: expanded,
          strings: strings,
          lines: NexCardDensity.of(context).lines,
          voiceLength: !marked,
        );
    if (!marked) return preview;
    final length = note.type == NoteType.voice && (note.durationMs ?? 0) > 0
        ? note.durationMs!
        : null;
    final theme = Theme.of(context);
    final marks = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (length != null) ...[
          Text(
            strings.durationLabel?.call(length) ??
                '${length ~/ 60000}:'
                    '${(length ~/ 1000 % 60).toString().padLeft(2, '0')}',
            textDirection: TextDirection.ltr,
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(width: NexSpacing.sm),
        ],
        // A reminder still to come stays in the accent: it is the one thing
        // here that asks for something.
        if (due != null)
          Flexible(
            child: _DueChip(
              due: due,
              label: strings.dueLabel?.call(due, note.dueRepeat),
              // A lapsed reminder is not an alarm any more. A repeating one
              // never lapses: it is always about to happen again.
              upcoming:
                  note.dueRepeat != NoteRepeat.once ||
                  due.isAfter(DateTime.now().toUtc()),
            ),
          ),
        if (due != null && attached) const SizedBox(width: NexSpacing.sm),
        if (attached)
          _AttachedMark(label: strings.attachedShort(note.attachmentCount)),
      ],
    );
    final line = nexCardPreviewLineHeightFor(context);
    if (expanded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          preview,
          SizedBox(
            height: line,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: marks,
            ),
          ),
        ],
      );
    }
    final ambient = Directionality.of(context);
    // Where the words end: the far side from where they start. A checklist's
    // and a link's rows keep the interface's sides whatever they say.
    final start = note.type == NoteType.checklist || note.type == NoteType.link
        ? ambient
        : nexDirectionOf(NexMarkdownText.preview(note.displayText ?? '')) ??
              ambient;
    return _Tucked(
      end: start == TextDirection.rtl ? _Side.left : _Side.right,
      top: note.type == NoteType.checklist,
      line: line,
      children: [preview, marks],
    );
  }
}

enum _Side { left, right }

/// The words, with the marks tucked into one corner of them — the end of
/// the last line, or of the first — and the words fading out just before
/// the marks, so a long line never runs underneath them.
///
/// Its own layout because the fade has to know how wide the marks came out,
/// and that is only known once they are laid out.
class _Tucked extends MultiChildRenderObjectWidget {
  const _Tucked({
    required this.end,
    required this.top,
    required this.line,
    required super.children,
  });

  final _Side end;
  final bool top;
  final double line;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTucked(end: end, top: top, line: line);

  @override
  void updateRenderObject(BuildContext context, _RenderTucked renderObject) {
    renderObject
      ..end = end
      ..top = top
      ..line = line;
  }
}

class _TuckedData extends ContainerBoxParentData<RenderBox> {}

class _RenderTucked extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TuckedData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TuckedData> {
  _RenderTucked({required _Side end, required bool top, required double line})
    : _end = end,
      _top = top,
      _line = line;

  /// How far the words take to fade out before the marks.
  static const _fade = NexSpacing.lg;

  _Side _end;
  set end(_Side value) {
    if (value == _end) return;
    _end = value;
    markNeedsLayout();
  }

  bool _top;
  set top(bool value) {
    if (value == _top) return;
    _top = value;
    markNeedsLayout();
  }

  double _line;
  set line(double value) {
    if (value == _line) return;
    _line = value;
    markNeedsLayout();
  }

  RenderBox get _words => firstChild!;
  RenderBox get _marks => childAfter(firstChild!)!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TuckedData) child.parentData = _TuckedData();
  }

  BoxConstraints _wordsConstraints(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: constraints.maxWidth,
        maxWidth: constraints.maxWidth,
        maxHeight: constraints.maxHeight,
      );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final words = _words.getDryLayout(_wordsConstraints(constraints));
    return constraints.constrain(Size(constraints.maxWidth, words.height));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _words.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _words.getMaxIntrinsicHeight(width);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _marks.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _words.getMaxIntrinsicWidth(height);

  /// The row the marks share with the words.
  Rect _row() {
    final height = math.min(_line, size.height);
    return Rect.fromLTWH(
      0,
      _top ? 0 : size.height - height,
      size.width,
      height,
    );
  }

  @override
  void performLayout() {
    final words = _words
      ..layout(_wordsConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(Size(constraints.maxWidth, words.size.height));
    (words.parentData! as _TuckedData).offset = Offset.zero;
    final marks = _marks
      ..layout(
        BoxConstraints(maxWidth: size.width * 0.6, maxHeight: _line),
        parentUsesSize: true,
      );
    final row = _row();
    (marks.parentData! as _TuckedData).offset = Offset(
      _end == _Side.left ? 0 : size.width - marks.size.width,
      row.top + (row.height - marks.size.height) / 2,
    );
  }

  @override
  bool get alwaysNeedsCompositing => true;

  final _hollow = LayerHandle<ShaderMaskLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    final row = _row();
    final width = math.min(size.width, _marks.size.width + _fade);
    final hollow = Rect.fromLTWH(
      _end == _Side.left ? 0 : size.width - width,
      row.top,
      width,
      row.height,
    );
    final fade = _fade / width;
    // Drawn over the words with "destination out": clear where it is solid,
    // so the words go under the marks and fade over the stretch before them.
    final shader = LinearGradient(
      begin: _end == _Side.left ? Alignment.centerRight : Alignment.centerLeft,
      end: _end == _Side.left ? Alignment.centerLeft : Alignment.centerRight,
      colors: const [Color(0x00000000), Color(0xFF000000)],
      stops: [0, fade],
    ).createShader(Offset.zero & hollow.size);
    _hollow.layer = (_hollow.layer ?? ShaderMaskLayer())
      ..shader = shader
      ..maskRect = hollow.shift(offset)
      ..blendMode = BlendMode.dstOut;
    context.pushLayer(
      _hollow.layer!,
      (context, offset) => context.paintChild(_words, offset),
      offset,
    );
    context.paintChild(
      _marks,
      offset + (_marks.parentData! as _TuckedData).offset,
    );
  }

  @override
  void dispose() {
    _hollow.layer = null;
    super.dispose();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// The files a note carries after its own, in the card's footnote: a
/// paperclip and "+3". Not on the leading square, whose corners already hold
/// the tag dots and the pin. Announced with the card (see `attachedLabel`),
/// so the mark itself is silent.
class _AttachedMark extends StatelessWidget {
  const _AttachedMark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The bell on a card, and when it will ring.
///
/// It was the bell on its own, which said a reminder existed and nothing
/// about it — so the only thing anyone could do with a reminder they could not
/// read was delete it. Every app that sets reminders on a list row puts the
/// time on the row.
///
/// The text is optional and the bell is not: a caller with no localisation
/// still gets the mark it always had.
class _DueChip extends StatelessWidget {
  const _DueChip({
    required this.due,
    required this.label,
    required this.upcoming,
  });

  final DateTime due;
  final String? label;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = upcoming
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final text = label;
    if (text == null) {
      return Icon(Icons.notifications_active_outlined, size: 14, color: color);
    }
    // No box of its own: a line of the card's footnote, not a chip on it.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.notifications_active_outlined, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
