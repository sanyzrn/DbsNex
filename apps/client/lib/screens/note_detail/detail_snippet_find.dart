part of '../note_detail_sheet.dart';

class _SnippetFindSheet extends StatefulWidget {
  const _SnippetFindSheet({required this.snippet});

  final NexCodeSnippet snippet;

  @override
  State<_SnippetFindSheet> createState() => _SnippetFindSheetState();
}

class _SnippetFindSheetState extends State<_SnippetFindSheet> {
  static const _limit = 200;
  final _controller = TextEditingController();
  List<({int line, String excerpt})> _matches = const [];
  bool _limited = false;
  int _searchId = 0;

  Future<void> _find(String query) async {
    final id = ++_searchId;
    final source = widget.snippet.code;
    final matches = query.isNotEmpty && source.length > 12000
        ? await compute(_findSnippetLines, (source, query))
        : _findSnippetLines((source, query));
    if (!mounted || id != _searchId) return;
    setState(() {
      _matches = matches.take(_limit).toList(growable: false);
      _limited = matches.length > _limit;
    });
  }

  static List<({int line, String excerpt})> _findSnippetLines(
    (String, String) request,
  ) {
    final (source, query) = request;
    if (query.isEmpty) return const [];
    final matches = <({int line, String excerpt})>[];
    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    var line = 1;
    var start = 0;
    while (start <= source.length) {
      final newline = source.indexOf('\n', start);
      final end = newline < 0 ? source.length : newline;
      final text = source.substring(start, end);
      final offset = text.indexOf(pattern);
      if (offset >= 0) {
        final from = math.max(0, offset - 60);
        final to = math.min(text.length, offset + query.length + 120);
        matches.add((
          line: line,
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
              onChanged: (query) => unawaited(_find(query)),
            ),
            if (_limited)
              Padding(
                padding: const EdgeInsets.only(top: NexSpacing.sm),
                child: Text(l10n.codeFirstMatches(_limit)),
              ),
            Expanded(
              child: _matches.isEmpty && _controller.text.isNotEmpty
                  ? Center(child: Text(l10n.codeNoMatches))
                  : ListView.builder(
                      itemCount: _matches.length,
                      itemBuilder: (context, index) {
                        final result = _matches[index];
                        return ListTile(
                          leading: Text('${result.line}'),
                          title: NexCodeText(
                            result.excerpt,
                            softWrap: true,
                            selectable: true,
                          ),
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
