part of '../note_detail_sheet.dart';

extension _DetailSnippet on _NoteDetailSheetState {
  NexCodeSnippet? _snippetFor(Note note) {
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
    return CustomScrollView(
      shrinkWrap: true,
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
              _SnippetReader(key: ValueKey(note.id), snippet: snippet),
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

/// Draws one continuous code block while laying out and highlighting only
/// the chunks near the viewport. Copy and share use the original snippet.
class _SnippetReader extends StatefulWidget {
  const _SnippetReader({super.key, required this.snippet});

  final NexCodeSnippet snippet;

  @override
  State<_SnippetReader> createState() => _SnippetReaderState();
}

class _SnippetReaderState extends State<_SnippetReader> {
  late List<int> _boundaries = _chunkBoundaries(widget.snippet.code);
  bool _highlight = false;
  Animation<double>? _entrance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation == _entrance && animation != null) return;
    _entrance?.removeStatusListener(_onEntrance);
    _entrance = animation;
    _highlight =
        animation == null || animation.status == AnimationStatus.completed;
    if (!_highlight) animation?.addStatusListener(_onEntrance);
  }

  void _onEntrance(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _entrance?.removeStatusListener(_onEntrance);
    setState(() => _highlight = true);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = widget.snippet.code;
    final style = theme.textTheme.bodyMedium?.copyWith(height: 1.55);
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      sliver: SliverPadding(
        padding: const EdgeInsets.all(NexSpacing.sm),
        sliver: SliverList.builder(
          itemCount: _boundaries.length - 1,
          addAutomaticKeepAlives: false,
          itemBuilder: (context, index) {
            final start = _boundaries[index];
            var end = _boundaries[index + 1];
            // The next widget already starts on a new line. Leave the last
            // line break in place at the end of the original source.
            if (end < source.length && source.codeUnitAt(end - 1) == 0x0a) {
              end--;
              if (end > start && source.codeUnitAt(end - 1) == 0x0d) end--;
            }
            return NexCodeText(
              source.substring(start, end),
              language: widget.snippet.language,
              highlight: _highlight,
              style: style,
              softWrap: true,
            );
          },
        ),
      ),
    );
  }
}
