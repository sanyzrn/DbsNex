part of '../note_detail_sheet.dart';

typedef _SnippetMatch = ({int line, int offset, int length, String excerpt});

class _SnippetFindSheet extends StatefulWidget {
  const _SnippetFindSheet({required this.snippet});

  final NexCodeSnippet snippet;

  @override
  State<_SnippetFindSheet> createState() => _SnippetFindSheetState();
}

class _SnippetFindSheetState extends State<_SnippetFindSheet> {
  static const _limit = 200;
  static const _pause = Duration(milliseconds: 140);
  final _controller = TextEditingController();
  List<_SnippetMatch> _matches = const [];
  bool _limited = false;
  bool _searching = false;
  int _searchId = 0;
  Timer? _debounce;

  void _schedule(String query) {
    final id = ++_searchId;
    _debounce?.cancel();
    final searching = query.isNotEmpty;
    if (_searching != searching || _matches.isNotEmpty) {
      setState(() {
        _matches = const [];
        _limited = false;
        _searching = searching;
      });
    }
    if (!searching) return;
    _debounce = Timer(_pause, () => unawaited(_find(query, id)));
  }

  Future<void> _find(String query, int id) async {
    final source = widget.snippet.code;
    List<_SnippetMatch> matches;
    if (source.length > 12000) {
      try {
        matches = await compute(_findSnippetLines, (source, query));
      } catch (_) {
        if (!mounted || id != _searchId) return;
        matches = _findSnippetLines((source, query));
      }
    } else {
      matches = _findSnippetLines((source, query));
    }
    if (!mounted || id != _searchId) return;
    setState(() {
      _searching = false;
      _matches = matches.take(_limit).toList(growable: false);
      _limited = matches.length > _limit;
    });
  }

  static List<_SnippetMatch> _findSnippetLines((String, String) request) {
    final (source, query) = request;
    if (query.isEmpty) return const [];
    final matches = <_SnippetMatch>[];
    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    var line = 1;
    var start = 0;
    while (start <= source.length) {
      final newline = source.indexOf('\n', start);
      final end = newline < 0 ? source.length : newline;
      final text = source.substring(start, end);
      if (pattern.firstMatch(text) case final match?) {
        final from = math.max(0, match.start - 60);
        final to = math.min(text.length, match.end + 120);
        matches.add((
          line: line,
          offset: start + match.start,
          length: match.end - match.start,
          excerpt:
              '${from > 0 ? '…' : ''}${text.substring(from, to)}${to < text.length ? '…' : ''}',
        ));
        if (matches.length > _limit) break;
      }
      if (newline < 0) break;
      start = newline + 1;
      line++;
    }
    return matches;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NexSheetBody(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NexSearchField(
              controller: _controller,
              hintText: l10n.codeFind,
              autofocus: true,
              private: true,
              textDirection: TextDirection.ltr,
              onChanged: _schedule,
            ),
            if (_limited)
              Padding(
                padding: const EdgeInsets.only(top: NexSpacing.sm),
                child: Text(l10n.codeFirstMatches(_limit)),
              ),
            Expanded(
              child:
                  !_searching && _matches.isEmpty && _controller.text.isNotEmpty
                  ? Center(child: Text(l10n.codeNoMatches))
                  : ListView.builder(
                      itemCount: _matches.length,
                      itemBuilder: (context, index) {
                        final result = _matches[index];
                        return ListTile(
                          leading: Text('${result.line}'),
                          title: NexCodeText(result.excerpt, softWrap: true),
                          onTap: () => Navigator.pop(context, result),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
