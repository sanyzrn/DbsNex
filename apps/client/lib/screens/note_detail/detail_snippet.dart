part of '../note_detail_sheet.dart';

extension _DetailSnippet on _NoteDetailSheetState {
  NexCodeSnippet? _snippetFor(Note note) {
    if (note.type != NoteType.text) return null;
    final source = note.content;
    if (_parsedSnippetSource != source) {
      _parsedSnippetSource = source;
      _parsedSnippet = source == null ? null : NexCodeSnippet.parse(source);
    }
    return _parsedSnippet;
  }

  Widget _snippetScroll(
    BuildContext context,
    Note note,
    NexCodeSnippet snippet,
    AppLocalizations l10n,
    EdgeInsets padding,
    List<Widget> header,
    List<Widget> footer,
  ) {
    final theme = Theme.of(context);
    // One controller for the sheet's life, so Find in code can scroll this
    // view to the chunk its line is in. [Scrollable.ensureVisible] cannot
    // do that alone: the list builds its chunks lazily, and a chunk far off
    // screen has no context to be shown.
    final scroll = _snippetScrollController ??= ScrollController();
    return CustomScrollView(
      shrinkWrap: true,
      controller: scroll,
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...header,
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nexCodeLanguageLabel(
                              context,
                              snippet.language,
                              rawLanguage: snippet.rawLanguage,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.codeFind,
                          icon: const Icon(Icons.search),
                          // The sheet returns the line a result was tapped
                          // on, and the reader scrolls to it: a list of
                          // matches nobody can reach is not a find.
                          onPressed: () => unawaited(
                            nexShowSheet<_SnippetMatch>(
                              context: context,
                              builder: (_) =>
                                  _SnippetFindSheet(snippet: snippet),
                            ).then((match) {
                              final reader = _snippetReader?.currentState;
                              if (match != null && reader != null) {
                                unawaited(reader.revealMatch(match));
                              }
                            }),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              unawaited(nexCopy(context, snippet.code)),
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          label: Text(l10n.copyCode),
                        ),
                      ],
                    ),
                    const SizedBox(height: NexSpacing.xs),
                  ],
                ),
              ),
              _SnippetReader(
                key: _snippetReader ??= GlobalKey<_SnippetReaderState>(
                  debugLabel: 'snippet-reader',
                ),
                snippet: snippet,
                scroll: scroll,
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.preferences case final prefs?
                        when AiChatSheet.availableFor(prefs))
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          icon: const Icon(Icons.forum_outlined, size: 18),
                          label: Text(l10n.askAboutCode),
                          onPressed: () => _askAbout(note, prefs),
                        ),
                      ),
                    ...footer,
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sources below this length are coloured on the sheet's frame. Longer ones
/// are coloured off the UI isolate and the chunks stay plain until it returns:
/// a long paste opens at once rather than waiting for its colours.
const _syncHighlightLimit = 12000;

typedef _ReaderRequest = ({
  String source,
  NexCodeLanguage language,
  ColorScheme scheme,
  List<int> boundaries,
});

int _chunkTextEnd(String source, List<int> boundaries, int index) {
  var end = boundaries[index + 1];
  if (end < source.length && source.codeUnitAt(end - 1) == 0x0a) {
    end--;
    if (end > boundaries[index] && source.codeUnitAt(end - 1) == 0x0d) end--;
  }
  return end;
}

/// Tokenize once so comments and strings keep their style across chunks.
/// Partition on the same isolate to keep large-file work off the UI thread.
List<List<TextSpan>> _snippetHighlight(_ReaderRequest request) {
  final spans = nexHighlightCode(
    request.source,
    request.language,
    style: const TextStyle(),
    scheme: request.scheme,
  );
  return [
    for (var i = 0; i < request.boundaries.length - 1; i++)
      nexSliceCodeSpans(
        spans,
        request.boundaries[i],
        _chunkTextEnd(request.source, request.boundaries, i),
      ),
  ];
}

class _SnippetReader extends StatefulWidget {
  const _SnippetReader({
    super.key,
    required this.snippet,
    required this.scroll,
  });

  final NexCodeSnippet snippet;

  /// The scroll view the reader's chunks sit in, for [revealLine].
  final ScrollController scroll;

  @override
  State<_SnippetReader> createState() => _SnippetReaderState();
}

class _SnippetReaderState extends State<_SnippetReader> {
  late List<int> _boundaries = _chunkBoundaries(widget.snippet.code);
  late int _previewEnd = _previewLimit(widget.snippet.code);
  bool? _showAll;
  bool get _canFold => _previewEnd < widget.snippet.code.length;
  bool get _expanded => !_canFold || _showAll == true;
  late List<int> _chunkLines = _firstLines(widget.snippet.code, _boundaries);
  bool _wrap = true;
  bool _numbered = false;
  bool _highlight = false;
  Animation<double>? _entrance;

  final _chunkKeys = <int, GlobalKey>{};
  final _targetText = GlobalKey();
  _SnippetMatch? _target;
  int _targetTextOffset = 0;

  GlobalKey _chunkKey(int index) =>
      _chunkKeys.putIfAbsent(index, GlobalKey.new);

  Future<void> revealMatch(_SnippetMatch match) async {
    final duration = NexMotion.of(context, NexMotion.standard);
    final code = widget.snippet.code;
    final chunk = _chunkAt(match.offset);
    _target = match;
    _setExpanded(true);
    await WidgetsBinding.instance.endOfFrame;

    bool current() =>
        mounted &&
        _target == match &&
        code == widget.snippet.code &&
        widget.scroll.hasClients;

    if (!current()) return;
    final position = widget.scroll.position;
    var lower = position.minScrollExtent;
    double? upper;
    var probe = position.maxScrollExtent * (match.line - 1) / _chunkLines.last;

    // The sliver estimates its extent from the chunks it has laid out.
    // Probe the estimate, then narrow the search using mounted chunk indices.
    // Usually the first probe is enough; wrapped text can skew it.
    for (
      var attempt = 0;
      attempt < 32 && _targetText.currentContext == null;
      attempt++
    ) {
      position.jumpTo(
        probe.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!current()) return;
      final visible = _chunkKeys.entries
          .where((e) => e.value.currentContext != null)
          .map((e) => e.key);
      final first = visible.isEmpty ? null : visible.reduce(math.min);
      final pixels = position.pixels;
      if ((first != null && first > chunk) ||
          (first == null && position.extentAfter < 1)) {
        upper = upper == null ? pixels : math.min(upper, pixels);
      } else {
        lower = math.max(lower, pixels);
      }
      final ceiling = math.min(
        upper ?? position.maxScrollExtent,
        position.maxScrollExtent,
      );
      if (ceiling - lower < 0.5) break;
      probe = upper == null ? ceiling : (lower + ceiling) / 2;
    }

    if (!current()) return;
    final render = _targetText.currentContext?.findRenderObject();
    if (render is! RenderParagraph) return;
    final start = match.offset - _targetTextOffset;
    final end = math.min(
      start + match.length,
      render.text.toPlainText().length,
    );
    if (end <= start) return;
    final boxes = render.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    if (boxes.isEmpty) return;
    // Reveal the matching glyphs, including their horizontal offset when the
    // chunk is unwrapped. Flutter propagates this rectangle to both viewports.
    render.showOnScreen(
      rect: boxes.first.toRect(),
      duration: duration,
      curve: NexMotion.curve,
    );
  }

  int _chunkAt(int offset) {
    var low = 0;
    var high = _boundaries.length - 1;
    while (high - low > 1) {
      final middle = (low + high) ~/ 2;
      if (_boundaries[middle] <= offset) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low;
  }

  _ReaderRequest? _requested;
  List<List<TextSpan>>? _chunkSpans;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation != _entrance || animation == null) {
      _entrance?.removeStatusListener(_onEntrance);
      _entrance = animation;
      _highlight =
          animation == null || animation.status == AnimationStatus.completed;
      if (!_highlight) animation?.addStatusListener(_onEntrance);
    }
    // Also on a theme change, which arrives here with the same animation.
    _prepareSpans();
  }

  void _onEntrance(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _entrance?.removeStatusListener(_onEntrance);
    if (!mounted) return;
    setState(() => _highlight = true);
    _prepareSpans();
  }

  /// Colours the whole snippet once, when the sheet has finished opening.
  void _prepareSpans() {
    if (!_highlight || !_expanded) return;
    final snippet = widget.snippet;
    if (snippet.language == NexCodeLanguage.plainText) {
      _requested = null;
      _chunkSpans = null;
      return;
    }
    final request = (
      source: snippet.code,
      language: snippet.language,
      scheme: Theme.of(context).colorScheme,
      boundaries: _boundaries,
    );
    if (_requested == request) return;
    _requested = request;
    if (snippet.code.length <= _syncHighlightLimit) {
      _chunkSpans = _snippetHighlight(request);
    } else {
      _chunkSpans = null;
      unawaited(_highlightOffThread(request));
    }
  }

  Future<void> _highlightOffThread(_ReaderRequest request) async {
    try {
      final chunks = await compute(_snippetHighlight, request);
      if (mounted && _requested == request) {
        setState(() => _chunkSpans = chunks);
      }
    } catch (_) {
      // Keep the source readable and allow a later dependency change to retry.
      if (_requested == request) _requested = null;
    }
  }

  @override
  void dispose() {
    _entrance?.removeStatusListener(_onEntrance);
    super.dispose();
  }

  @override
  void didUpdateWidget(_SnippetReader old) {
    super.didUpdateWidget(old);
    if (old.snippet.code != widget.snippet.code) {
      _boundaries = _chunkBoundaries(widget.snippet.code);
      _previewEnd = _previewLimit(widget.snippet.code);
      _chunkLines = _firstLines(widget.snippet.code, _boundaries);
      // The old chunks are gone; keys for chunks that no longer exist
      // must not outlive them.
      _chunkKeys.clear();
      _target = null;
    }
    if (old.snippet != widget.snippet) {
      _prepareSpans();
    }
  }

  static List<int> _chunkBoundaries(String source) {
    final boundaries = [0];
    while (boundaries.last < source.length) {
      boundaries.add(_chunkEnd(source, boundaries.last));
    }
    return boundaries;
  }

  static int _chunkEnd(String source, int start) {
    final limit = math.min(start + 4000, source.length);
    var lines = 0;
    var lastBreak = start;
    for (var i = start; i < limit; i++) {
      if (source.codeUnitAt(i) == 0x0a) {
        lastBreak = i + 1;
        if (++lines == 48) return lastBreak;
      }
    }
    if (limit == source.length) return limit;
    if (source.startsWith('\r\n', limit)) return limit + 2;
    if (source.codeUnitAt(limit) == 0x0a) return limit + 1;
    if (lastBreak > start) return lastBreak;
    final last = source.codeUnitAt(limit - 1);
    final splitsSurrogate = (last & 0xfc00) == 0xd800;
    return splitsSurrogate ? limit - 1 : limit;
  }

  static int _previewLimit(String source) {
    final limit = math.min(source.length, 480);
    var lines = 0;
    for (var i = 0; i < limit; i++) {
      if (source.codeUnitAt(i) == 0x0a &&
          ++lines == 8 &&
          i + 1 < source.length) {
        return i;
      }
    }
    if (limit < source.length &&
        (source.codeUnitAt(limit - 1) & 0xfc00) == 0xd800) {
      return limit - 1;
    }
    return limit;
  }

  static List<int> _firstLines(String source, List<int> boundaries) {
    var line = 1;
    final firstLines = <int>[];
    for (var i = 0; i < boundaries.length - 1; i++) {
      firstLines.add(line);
      for (var j = boundaries[i]; j < boundaries[i + 1]; j++) {
        if (source.codeUnitAt(j) == 0x0a) line++;
      }
    }
    return [...firstLines, line];
  }

  void _setExpanded(bool value) {
    setState(() => _showAll = value);
    _prepareSpans();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final source = widget.snippet.code;
    final style = theme.textTheme.bodyMedium?.copyWith(height: 1.55);

    return DecoratedSliver(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      sliver: SliverPadding(
        padding: const EdgeInsets.all(NexSpacing.sm),
        sliver: SliverMainAxisGroup(
          slivers: [
            if (_expanded)
              SliverToBoxAdapter(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    children: [
                      IconButton(
                        tooltip: l10n.codeLineNumbers,
                        visualDensity: VisualDensity.compact,
                        isSelected: _numbered,
                        icon: const Icon(Icons.format_list_numbered),
                        onPressed: () => setState(() => _numbered = !_numbered),
                      ),
                      IconButton(
                        tooltip: l10n.codeWrap,
                        visualDensity: VisualDensity.compact,
                        isSelected: _wrap,
                        icon: const Icon(Icons.wrap_text),
                        onPressed: () => setState(() => _wrap = !_wrap),
                      ),
                    ],
                  ),
                ),
              ),
            if (_expanded && _canFold)
              SliverToBoxAdapter(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('snippet-expand'),
                    onPressed: () => _setExpanded(!_expanded),
                    icon: const Icon(Icons.expand_less),
                    label: Text(l10n.codeShowLess),
                  ),
                ),
              ),
            if (!_expanded)
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NexCodeText(
                      source.substring(0, _previewEnd),
                      language: widget.snippet.language,
                      highlight: _highlight,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                      softWrap: true,
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const ValueKey('snippet-expand'),
                        onPressed: () => _setExpanded(true),
                        icon: const Icon(Icons.expand_more),
                        label: Text(l10n.codeShowMore),
                      ),
                    ),
                  ],
                ),
              )
            else
              SliverList.builder(
                itemCount: _boundaries.length - 1,
                addAutomaticKeepAlives: false,
                itemBuilder: (context, index) {
                  final start = _boundaries[index];
                  final end = _chunkTextEnd(source, _boundaries, index);
                  final chunk = source.substring(start, end);
                  final spans = _chunkSpans?[index];
                  final body = _numbered
                      ? _numberedChunk(chunk, index, spans, style)
                      : _codeText(chunk, spans, style, sourceOffset: start);
                  return KeyedSubtree(
                    key: _chunkKey(index),
                    child: _wrap
                        ? body
                        : Directionality(
                            textDirection: TextDirection.ltr,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: body,
                            ),
                          ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _codeText(
    String text,
    List<TextSpan>? spans,
    TextStyle? style, {
    required int sourceOffset,
  }) {
    final target = _target?.offset;
    final containsMatch =
        target != null &&
        target >= sourceOffset &&
        target < sourceOffset + text.length;
    if (containsMatch) _targetTextOffset = sourceOffset;
    return NexCodeText(
      text,
      key: containsMatch ? _targetText : null,
      language: widget.snippet.language,
      highlight: false,
      spans: spans,
      style: style,
      softWrap: _wrap,
    );
  }

  Widget _numberedChunk(
    String chunk,
    int index,
    List<TextSpan>? spans,
    TextStyle? style,
  ) {
    final scheme = Theme.of(context).colorScheme;
    var number = _chunkLines[index];
    final width = _chunkLines.last.toString().length + 2;
    var start = 0;
    final rows = <Widget>[];
    for (final line in chunk.split('\n')) {
      final text = line.endsWith('\r')
          ? line.substring(0, line.length - 1)
          : line;
      final end = start + text.length;
      final sourceOffset = _boundaries[index] + start;
      final continues =
          start == 0 &&
          sourceOffset > 0 &&
          widget.snippet.code.codeUnitAt(sourceOffset - 1) != 0x0a;
      final gutter = continues ? '' : '$number';
      final code = _codeText(
        text.isEmpty ? ' ' : text,
        spans == null || text.isEmpty
            ? null
            : nexSliceCodeSpans(spans, start, end),
        style,
        sourceOffset: sourceOffset,
      );
      rows.add(
        Row(
          mainAxisSize: _wrap ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Text(
                gutter.padLeft(width),
                style: NexCodeText.monospaceStyle(style)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: NexSpacing.sm),
            if (_wrap) Expanded(child: code) else code,
          ],
        ),
      );
      start += line.length + 1;
      number++;
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}
