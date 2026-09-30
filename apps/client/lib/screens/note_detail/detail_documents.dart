part of '../note_detail_sheet.dart';

/// How a `.docx` becomes Markdown.
///
/// A variable rather than a direct call, for a testing reason said out loud:
/// `flutter_test` runs a widget test's body in a fake-async zone, and work
/// handed to another isolate does not report back into it. With the real
/// reader in place the only thing a widget test could ever assert about this
/// preview is that it is still loading — which is exactly the part that was
/// never in doubt. Tests swap in a same-isolate reader; nothing else does.
@visibleForTesting
Future<NexDocxText?> Function(List<int> bytes) nexDocxReader = (bytes) =>
    Isolate.run(() => NexDocx.read(bytes));

/// A `.docx`, read into Markdown and rendered like any other document in a
/// note.
///
/// Off the main thread, unlike every other preview here. A `.docx` is
/// compressed, so the file's size says little about how much work opening it
/// is: unzipping and parsing a few hundred kilobytes of XML is not a fraction
/// of a frame the way reading half a megabyte of plain text is. So this one
/// waits, and shows that it is waiting.
///
/// Only `.docx` for now. The other document kinds — PDF above all — reach this
/// widget and render nothing, exactly as they did before, because showing them
/// needs a renderer this app does not carry.
class _DocumentBody extends StatefulWidget {
  const _DocumentBody({required this.path});

  final String path;

  @override
  State<_DocumentBody> createState() => _DocumentBodyState();
}

class _DocumentBodyState extends State<_DocumentBody> {
  NexDocxText? _document;
  String? _error;
  bool _tooLarge = false;
  bool _unreadable = false;
  bool _loading = false;

  /// The only document format with a reader here. Everything else stays a
  /// named file, which is what it was.
  bool get _readable => NexFileKinds.extensionOf(widget.path) == 'docx';

  @override
  void initState() {
    super.initState();
    // Assigned rather than set: `setState` inside `initState` — or inside
    // `didUpdateWidget` — fires during a build, which Flutter rejects. A
    // rebuild is already coming in both cases.
    _loading = _readable;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_DocumentBody old) {
    super.didUpdateWidget(old);
    if (old.path == widget.path) return;
    _document = null;
    _error = null;
    _tooLarge = false;
    _unreadable = false;
    _loading = _readable;
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!_readable) return;
    final path = widget.path;
    NexDocxText? read;
    String? error;
    var tooLarge = false;
    try {
      final file = File(path);
      if (file.existsSync()) {
        if (file.lengthSync() > NexDocx.maxBytes) {
          tooLarge = true;
        } else {
          // Read synchronously, parsed elsewhere. The read is bounded by
          // the cap just checked and costs what the other previews' reads
          // cost; the parse is the expensive half, and it is the half that
          // leaves the main thread. See the class comment: a `.docx` is
          // compressed, so its size on disk says little about the work of
          // opening it.
          final bytes = file.readAsBytesSync();
          try {
            read = await nexDocxReader(bytes);
          } on Object {
            // Spawning an isolate can fail for reasons that have nothing to
            // do with this document. That is a reason to do the work here and
            // wear the pause, not a reason to refuse to show the file — the
            // parse itself reports its own failures by returning null.
            read = NexDocx.read(bytes);
          }
        }
      }
    } catch (caught) {
      error = '$caught';
    }
    // The path can have changed while the isolate was working — the sheet is
    // reused across notes — and writing this answer onto a different file
    // would be worse than dropping it.
    if (!mounted || widget.path != path) return;
    setState(() {
      _document = read;
      _error = error;
      _tooLarge = tooLarge;
      _unreadable = !tooLarge && error == null && read == null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_readable) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget say(String message) => Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Text(message, style: quiet),
    );

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: NexSpacing.sm),
        child: NexSkeleton(height: 16),
      );
    }
    if (_tooLarge) return say(l10n.filePreviewTooLarge);
    if (_error != null) return say(l10n.filePreviewUnreadable(_error!));
    if (_unreadable) return say(l10n.documentUnreadable);
    final document = _document;
    if (document == null || document.markdown.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionArea(
            contextMenuBuilder: nexSelectionMenu,
            child: NexMarkdown(
              document.markdown,
              selectable: false,
              onTapLink: _openHref,
              onCopyCode: (code) => unawaited(_copyCodeSpan(context, code)),
            ),
          ),
          // A document that stops early with nothing said about it reads as a
          // document that is that short.
          if (document.truncated) say(l10n.documentTruncated),
        ],
      ),
    );
  }
}

/// Source and configuration, in the same block the Markdown renderer already
/// uses for a fenced block — so a `.dart` file and a code fence inside a `.md`
/// file look like the same thing, because they are.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge ?? const TextStyle();
    return Container(
      padding: const EdgeInsets.all(NexSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      // Source does not wrap. A line broken at the container's edge is a
      // different line from the one in the file, and where indentation carries
      // meaning it is a misleading one — so long lines scroll sideways, the
      // way every editor shows them.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // The [Directionality] as well as the argument, because the handles
        // over a selection are placed by the ambient direction: in a Persian
        // interface a left-to-right block came up with its two handles on the
        // wrong ends.
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SelectableText(
            text,
            contextMenuBuilder: nexReadingMenu,
            // Left to right whatever the interface is doing, and whatever the
            // strings inside the file are: source is written left to right,
            // and letting a Persian comment turn the block would put the
            // indentation of every line on the wrong side.
            textDirection: TextDirection.ltr,
            style: base.copyWith(
              // By family name rather than a bundled font, for the same
              // reason the Markdown renderer does it: the app ships one
              // typeface for its own text, and code that falls back to the
              // platform's mono is closer to right than code set in the body
              // face.
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Courier New', 'monospace'],
              fontSize: (base.fontSize ?? 16) - 1,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}

/// A `.csv` or `.tsv`, drawn as the table it is.
///
/// Borders, weights and padding are the ones the Markdown renderer uses for a
/// Markdown table, deliberately: a spreadsheet exported to CSV and a table
/// typed into a note are the same object to a reader.
class _DelimitedTable extends StatelessWidget {
  const _DelimitedTable({required this.rows, required this.omitted});

  final List<List<String>> rows;

  /// How many rows were left undrawn. Said out loud rather than trailing off:
  /// a table that stops at row 200 with no explanation reads as a file that
  /// ends at row 200.
  final int omitted;

  /// Past this, a cell wraps instead of stretching its column across the
  /// screen. One paragraph in one cell should not set the width of the table.
  static const _maxCellWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.textTheme.bodyLarge;
    final columns = rows.fold<int>(
      0,
      (widest, row) => row.length > widest ? row.length : widest,
    );
    if (columns == 0) return const SizedBox.shrink();
    // The same whole-document rule as the Markdown renderer: the direction
    // comes from what is written, not from the interface language, so a
    // Persian spreadsheet starts its first column on the right.
    final direction =
        nexDirectionOf(rows.first.join(' ')) ?? Directionality.of(context);
    return Directionality(
      textDirection: direction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: scheme.outlineVariant),
              children: [
                for (var r = 0; r < rows.length; r++)
                  TableRow(
                    children: [
                      for (var c = 0; c < columns; c++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: NexSpacing.sm,
                            vertical: NexSpacing.xs,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _maxCellWidth,
                            ),
                            child: Text(
                              // Ragged rows are left ragged by the parser
                              // rather than padded, so the short ones are
                              // filled in here — at the edge, where inventing
                              // an empty cell is a drawing decision and not a
                              // claim about the file.
                              c < rows[r].length ? rows[r][c] : '',
                              style: r == 0
                                  ? base?.copyWith(fontWeight: FontWeight.w700)
                                  : base,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (omitted > 0)
            Padding(
              padding: const EdgeInsets.only(top: NexSpacing.xs),
              child: Text(
                l10n.tableTruncated(rows.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
