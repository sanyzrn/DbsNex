part of '../note_detail_sheet.dart';

/// A snippet's reading body: one fixed-width block, its language, and the
/// copy action that copies the code and nothing around it.
extension _DetailSnippet on _NoteDetailSheetState {
  Widget _snippetBody(
    BuildContext context,
    Note note,
    NexCodeSnippet snippet,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => unawaited(nexCopy(context, snippet.code)),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: Text(l10n.copyCode),
            ),
          ],
        ),
        const SizedBox(height: NexSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(NexSpacing.sm),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(NexRadius.md),
          ),
          child: _SnippetReader(key: ValueKey(note.id), snippet: snippet),
        ),
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
      ],
    );
  }
}

/// Keep shaping and highlighting bounded even for a single enormous line.
/// Page boundaries prefer newlines and preserve every source character.
class _SnippetReader extends StatefulWidget {
  const _SnippetReader({super.key, required this.snippet});
  final NexCodeSnippet snippet;
  @override
  State<_SnippetReader> createState() => _SnippetReaderState();
}

class _SnippetReaderState extends State<_SnippetReader> {
  final _starts = [0];
  bool _wrap = false;
  @override
  void didUpdateWidget(_SnippetReader old) {
    super.didUpdateWidget(old);
    if (old.snippet.code != widget.snippet.code) {
      _starts.removeRange(1, _starts.length);
    }
  }

  int _pageEnd(String source, int start) {
    final limit = (start + 4000).clamp(start, source.length);
    var lines = 0;
    var lastBreak = start;
    for (var i = start; i < limit; i++) {
      if (source.codeUnitAt(i) == 10) {
        lastBreak = i + 1;
        if (++lines == 48) return lastBreak;
      }
    }
    if (limit == source.length) return limit;
    if (lastBreak > start) return lastBreak;
    final last = source.codeUnitAt(limit - 1);
    return ((last & 0xfc00) == 0xd800 ||
            last == 13 && source.codeUnitAt(limit) == 10)
        ? limit - 1
        : limit;
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.snippet.code;
    final start = _starts.last;
    final end = _pageEnd(source, start);
    final next = end < source.length;
    final nav = MaterialLocalizations.of(context);
    final block = Directionality(
      textDirection: TextDirection.ltr,
      child: NexCodeText(
        source.substring(start, end),
        language: widget.snippet.language,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55),
        softWrap: _wrap,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: AppLocalizations.of(context).codeWrap,
              isSelected: _wrap,
              icon: const Icon(Icons.wrap_text),
              onPressed: () => setState(() => _wrap = !_wrap),
            ),
            if (start > 0 || next) ...[
              const Spacer(),
              IconButton(
                tooltip: nav.previousPageTooltip,
                icon: const Icon(Icons.arrow_back),
                onPressed: start == 0
                    ? null
                    : () => setState(_starts.removeLast),
              ),
              Text(
                nexDigits(
                  '${_starts.length}',
                  persian: Localizations.localeOf(context).languageCode == 'fa',
                ),
              ),
              IconButton(
                tooltip: nav.nextPageTooltip,
                icon: const Icon(Icons.arrow_forward),
                onPressed: next ? () => setState(() => _starts.add(end)) : null,
              ),
            ],
          ],
        ),
        if (_wrap)
          block
        else
          Directionality(
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(
              key: ValueKey(start),
              scrollDirection: Axis.horizontal,
              child: block,
            ),
          ),
      ],
    );
  }
}
