part of 'note_grid_card.dart';

const _shortGridHeight = 152.0;
const _mediumGridHeight = 180.0;
const _gridCaptionGap = NexSpacing.xs;

double _scaleHeight(double height, TextScaler scaler) =>
    scaler.scale(height).clamp(height, height * 1.7);

TextStyle? _gridTitleStyle(TextTheme theme) =>
    theme.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3);

TextStyle? _gridBodyStyle(TextTheme theme) =>
    theme.bodySmall?.copyWith(height: 1.4);

String _gridCaption(Note note) => note.type == NoteType.text
    ? NexMarkdownText.preview(note.caption ?? '').trim()
    : '';

NexCodeSnippet? _gridCodePreview(Note note) => note.snippetPreview;

({String title, String body}) _gridWords(Note note, NexCardStrings strings) {
  final title = note.title?.trim() ?? '';
  // A named text note has its own body. displayText returns the name for it.
  if (note.type == NoteType.text && title.isNotEmpty) {
    return (
      title: title,
      body:
          note.snippetPreview?.code ??
          NexMarkdownText.preview(note.content ?? '').trim(),
    );
  }
  return nexSplitNoteText(note, strings);
}

typedef _GridTextLayout = ({
  TextStyle inherited,
  TextScaler scaler,
  Locale? locale,
  TextDirection direction,
  TextHeightBehavior? heightBehavior,
});

_GridTextLayout _gridTextLayoutOf(
  BuildContext context, {
  TextStyle? inherited,
}) => (
  inherited: inherited ?? DefaultTextStyle.of(context).style,
  scaler: MediaQuery.textScalerOf(context),
  locale: Localizations.maybeLocaleOf(context),
  direction: Directionality.of(context),
  heightBehavior: DefaultTextHeightBehavior.maybeOf(context),
);

List<double> _gridLineHeights(
  String text,
  TextStyle? style,
  double width,
  _GridTextLayout layout, {
  required int maxLines,
  TextDirection? direction,
}) {
  if (text.isEmpty) return const [];
  final painter = TextPainter(
    text: TextSpan(text: text, style: layout.inherited.merge(style)),
    textDirection: direction ?? nexDirectionOf(text) ?? layout.direction,
    textScaler: layout.scaler,
    locale: layout.locale,
    textHeightBehavior: layout.heightBehavior,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: width);
  final heights = [
    for (final line in painter.computeLineMetrics()) line.height,
  ];
  painter.dispose();
  return heights;
}

/// Everything that can change the height a preview needs. No context or
/// scroll position is used while the sliver lays out its rows.
class NexGridRowSizing {
  factory NexGridRowSizing.of(
    BuildContext context,
    NexCardStrings strings, {
    NexGridRowSizing? previous,
  }) {
    final candidate = NexGridRowSizing._(context, strings);
    return previous != null && previous._matches(candidate)
        ? previous
        : candidate;
  }

  NexGridRowSizing._(BuildContext context, this._strings)
    : _metrics = NexGridMetrics.of(context),
      _theme = Theme.of(context).textTheme,
      _layout = _gridTextLayoutOf(
        context,
        inherited: Theme.of(context).textTheme.bodyMedium,
      );

  final NexGridMetrics _metrics;
  final TextTheme _theme;
  final _GridTextLayout _layout;
  final NexCardStrings _strings;
  final _heights = Expando<({double width, double height})>();

  bool _matches(NexGridRowSizing other) =>
      identical(_metrics, other._metrics) &&
      _theme == other._theme &&
      _layout == other._layout;

  double _cachedHeightFor(Note note, double width, double labelHeight) {
    // Link art can have become available between two different note lists.
    if (note.type == NoteType.link) return _heightFor(note, width, labelHeight);
    final known = _heights[note];
    if (known != null && known.width == width) return known.height;
    final height = _heightFor(note, width, labelHeight);
    _heights[note] = (width: width, height: height);
    return height;
  }

  double _heightFor(Note note, double width, double labelHeight) {
    final scaler = _layout.scaler;
    final tall = _scaleHeight(_metrics.height, scaler);
    if (note.type == NoteType.photo ||
        nexTileBackdropOf(note) != NexTileBackdrop.none) {
      return tall;
    }

    final medium = _scaleHeight(_mediumGridHeight, scaler);
    final short = _scaleHeight(_shortGridHeight, scaler);
    final insets = 2 * (_metrics.padding + _gridBorderReserve);
    // Leave room for selection, time, tags and the reminder in every state.
    final foot = note.dueAt == null
        ? math.max(labelHeight, 8.0)
        : math.max(labelHeight, 13.0) + 6;
    final chrome =
        insets +
        math.max(_gridPickTarget, _metrics.disc) +
        _metrics.padding * 0.8 +
        NexSpacing.xs +
        foot;
    final shortRoom = short - chrome;
    final mediumRoom = medium - chrome;
    final bodyWidth = math.max(0.0, width - insets);
    final titleStyle = _gridTitleStyle(_theme);
    final bodyStyle = _gridBodyStyle(_theme);
    List<double> lines(String text, TextStyle? style, int limit) =>
        _gridLineHeights(text, style, bodyWidth, _layout, maxLines: limit);
    double total(List<double> values) =>
        values.fold(0.0, (sum, height) => sum + height);

    if (note.type == NoteType.checklist) {
      final items = note.checklistItems.where(
        (item) => item.text.trim().isNotEmpty,
      );
      final count = items.take(3).length;
      final sample = 'Ag آگ';
      final header = math.max(22.0, total(lines(sample, titleStyle, 1)));
      final item = math.max(30.0, total(lines(sample, bodyStyle, 1)));
      return count <= 2 && header + math.max(1, count) * item <= mediumRoom
          ? medium
          : tall;
    }

    final snippet = _gridCodePreview(note);
    final (:title, :body) = snippet == null
        ? _gridWords(note, _strings)
        : (title: note.title?.trim() ?? '', body: snippet.code);
    if (note.type == NoteType.link) {
      // A cover fetched while scrolling can paint into the existing tile.
      // Let it take a tall row when a new layout is assembled.
      final face = NexLinkFace.of(note.linkUrl ?? '');
      if (face.kind == NexLinkKind.video ||
          NexLinkArt.instance.of(note.id)?.cover != null) {
        return tall;
      }
      final headline = nexLinkHeadline(
        note,
        title.isNotEmpty ? title : body,
        face,
      );
      final heading = lines(headline, titleStyle, 4);
      final site = math.max(
        _gridSiteMark,
        total(lines('Ag آگ', bodyStyle, 1)) +
            (face.kind == NexLinkKind.page ? 0 : labelHeight),
      );
      final needed =
          site + (heading.isEmpty ? 0 : NexSpacing.sm + total(heading));
      if (heading.length <= 1 && needed <= shortRoom) return short;
      return heading.length <= 3 && needed <= mediumRoom ? medium : tall;
    }

    if (note.isAudioMedia && note.mediaUri?.isNotEmpty == true) {
      final words = title.isNotEmpty ? title : body;
      if (words.isEmpty && shortRoom >= _gridVoiceStrip) return short;
      final preview = lines(
        words,
        title.isNotEmpty ? titleStyle : bodyStyle,
        4,
      );
      final needed = _gridVoiceStrip + NexSpacing.xs + total(preview);
      return preview.length <= 3 && needed <= mediumRoom ? medium : tall;
    }

    final heading = lines(title, titleStyle, 3);
    final preview = snippet == null
        ? lines(body, bodyStyle, 5)
        : _gridLineHeights(
            body,
            NexCodeText.monospaceStyle(bodyStyle),
            bodyWidth,
            _layout,
            maxLines: 5,
            direction: TextDirection.ltr,
          );
    final caption = lines(_gridCaption(note), bodyStyle, 2);
    final lineCount = heading.length + preview.length + caption.length;
    final needed =
        total(heading) +
        total(preview) +
        total(caption) +
        (caption.isEmpty ? 0 : _gridCaptionGap);
    if (note.type != NoteType.file && lineCount <= 2 && needed <= shortRoom) {
      return short;
    }
    return lineCount <= 4 && needed <= mediumRoom ? medium : tall;
  }
}

/// Row geometry shared by the lazy grid and the day-fold animation.
///
/// Calculated once for these notes at their actual width. The scroll path
/// reuses the offsets and binary-searches the first/last visible row. A
/// group can keep this object through selection, a fold or other rebuilds.
class NexGridRows {
  NexGridRows(this._notes, this._sizing);

  final List<Note> _notes;
  final NexGridRowSizing _sizing;
  ({double width, bool reverse, _AdaptiveGridLayout layout})? _cached;

  bool matches(NexGridRowSizing sizing) => identical(_sizing, sizing);

  double heightAt(int row, double width, {required bool reverseCrossAxis}) =>
      _layoutFor(width, reverseCrossAxis)._heightAt(row);

  _AdaptiveGridLayout _layoutFor(double width, bool reverse) {
    final cached = _cached;
    if (cached != null && cached.width == width && cached.reverse == reverse) {
      return cached.layout;
    }
    final columns = _sizing._metrics.columnsFor(width);
    const gap = NexSpacing.sm;
    final tileWidth = math.max(0.0, width - (columns - 1) * gap) / columns;
    final labels = _gridLineHeights(
      'Ag آگ',
      _sizing._theme.labelSmall,
      tileWidth,
      _sizing._layout,
      maxLines: 1,
    );
    final labelHeight = labels.firstOrNull ?? 0.0;
    final tall = _scaleHeight(_sizing._metrics.height, _sizing._layout.scaler);
    final heights = <double>[];
    final offsets = [0.0];
    for (var first = 0; first < _notes.length; first += columns) {
      var height = 0.0;
      for (var i = first; i < math.min(first + columns, _notes.length); i++) {
        height = math.max(
          height,
          _sizing._cachedHeightFor(_notes[i], tileWidth, labelHeight),
        );
        if (height == tall) break;
      }
      heights.add(height);
      offsets.add(offsets.last + height + gap);
    }
    final layout = _AdaptiveGridLayout(
      columns: columns,
      tileWidth: tileWidth,
      reverse: reverse,
      offsets: offsets,
      heights: heights,
    );
    _cached = (width: width, reverse: reverse, layout: layout);
    return layout;
  }
}

class _AdaptiveGridLayout extends SliverGridLayout {
  const _AdaptiveGridLayout({
    required this.columns,
    required this.tileWidth,
    required this.reverse,
    required this.offsets,
    required this.heights,
  });

  final int columns;
  final double tileWidth;
  final bool reverse;
  final List<double> offsets;
  final List<double> heights;

  double _heightAt(int row) => row < heights.length ? heights[row] : 0.0;

  int _rowAt(double offset, {required bool includeStart}) {
    var low = 0;
    var high = offsets.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final start = offsets[mid];
      if (start < offset || (includeStart && start == offset)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return math.max(0, low - 1);
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) =>
      _rowAt(scrollOffset, includeStart: true) * columns;

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) => scrollOffset <= 0
      ? 0
      : (_rowAt(scrollOffset, includeStart: false) + 1) * columns - 1;

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    // Flutter asks for geometry one past the end before trying the builder.
    final row = math.min(index ~/ columns, heights.length);
    final position = index % columns;
    final column = reverse ? columns - 1 - position : position;
    return SliverGridGeometry(
      scrollOffset: offsets[row],
      crossAxisOffset: column * (tileWidth + NexSpacing.sm),
      mainAxisExtent: _heightAt(row),
      crossAxisExtent: tileWidth,
    );
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    if (childCount == 0 || heights.isEmpty) return 0.0;
    // The guard is local rather than an incident of layout and children
    // always being computed from the same list.
    final lastRow = math.min((childCount - 1) ~/ columns, heights.length - 1);
    return offsets[lastRow] + heights[lastRow];
  }
}
