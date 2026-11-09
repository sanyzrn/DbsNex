import 'package:nex_core/nex_core.dart';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'feature_label.dart';

/// A reading body that starts folded and opens to its whole text.
///
/// Past 900 characters or 12 lines, what is shown first is the first page
/// and a More button; the rest arrives on the tap. This is the one widget
/// every long piece of text in the app reads through — a text note, a
/// Markdown file, a converted document, a source file — so the costs it pays
/// are the costs of reading.
///
/// ## Opening
///
/// Expanding used to hand the whole document to the Markdown parser, the
/// widget tree and the text layout in the tap's own frame: a pause the
/// length of the document, with the tap on More its only evidence. The
/// opened page now arrives a slice at a time: the first slice — whole
/// blocks, never the inside of one — is built in the tap's frame, and the
/// rest over the frames that follow, so the reading starts the moment the
/// tap lands and the page grows while the eye is still on the first
/// paragraph.
///
/// Each slice is its own [RepaintBoundary], which is what keeps the opened
/// page cheap afterwards. Scrolling it, or opening a sheet over it — the
/// more-actions menu, the thread picker — composites cached layers instead
/// of re-recording one picture the size of the whole document on every
/// frame of the animation.
///
/// ## What is measured once
///
/// Whether a text is long, and where its fold falls, is decided by walking
/// its characters and lines. A sheet rebuilds on every action taken in it —
/// a caption edited, a tag added, an AI result arriving — and a document
/// that had not changed in between used to pay that walk again on each one.
/// Both answers, and the slices, are kept until the text — or its markdown
/// override — changes.
class FoldedNote extends StatefulWidget {
  const FoldedNote({
    super.key,
    required this.text,
    this.onTapLink,
    this.onHoldLink,
    this.onCopyCode,
    this.markdown,
    this.contentBuilder,
  });
  final String text;

  /// Null detects markup; text files keep their declared format.
  final bool? markdown;
  final Widget Function(BuildContext, String)? contentBuilder;
  final void Function(String)? onTapLink;
  final NexLinkHold? onHoldLink;
  final void Function(String)? onCopyCode;
  @override
  State<FoldedNote> createState() => _FoldedNoteState();
}

class _FoldedNoteState extends State<FoldedNote> {
  bool expanded = false;

  /// The text everything below was measured for, or null before the first
  /// build; same-text rebuilds answer from the cache.
  String? _preparedFor;

  /// The markdown override that cache was built under. It is constant for
  /// as long as a note is open — a file is the kind of file it is — but it
  /// is part of what the cached widgets render, so it belongs in the key.
  bool? _preparedMarkdown;
  bool _long = false;
  String _foldedText = '';

  /// The slices the text opens in, and the already-built widgets for them.
  /// A widget is built when its slice is first revealed and kept: the
  /// identical instance in the list is what lets the next reveal skip
  /// re-building everything above it.
  ///
  /// The theme is deliberately not part of what invalidates this cache: a
  /// kept slice still reads [Theme.of] in its own build, so a theme change
  /// reaches text that was built frames ago. Nor are the link callbacks:
  /// every caller rebuilds them as fresh closures on each build, and keying
  /// on their identity would rebuild every slice on every action in the
  /// sheet — the pause this widget exists to remove. A kept slice answers
  /// the callbacks it was built with, and every caller passes ones bound to
  /// the sheet that owns them, so the kept ones behave as the fresh ones
  /// would for as long as the sheet stands.
  List<String> _sliceTexts = const [];
  final List<Widget> _sliceWidgets = [];

  /// How many slices are built so far. Zero while folded; one on the tap,
  /// then a frame's worth of characters a frame until the page is whole.
  int _revealed = 0;

  /// How the opened document renders, and which way it reads — both decided
  /// once, off the whole text, exactly as the one body that used to render
  /// it decided them.
  bool _sliceMarkdown = false;
  TextDirection? _sliceDirection;

  /// Past this many characters or lines, the first page is all that shows.
  static const _foldCharacters = 900;
  static const _foldLines = 12;

  /// Slices grow to about this many characters before they are cut at the
  /// next blank line: big enough that a page is not a crowd of layers,
  /// small enough that building one is no more than a frame's work.
  static const _sliceTarget = 4 * 1024;

  /// Documents up to this many characters open in one piece, exactly as
  /// they always did. Slicing is for the sizes whose opening cost was a
  /// visible pause; on anything smaller it would only be its own edge
  /// cases.
  static const _sliceOnlyAbove = 6 * 1024;

  /// How much text one frame of the reveal may build: about eight
  /// kilobytes, a frame's worth of Markdown parsing and layout on a phone,
  /// so a long document is whole in about a second. Budgeted in characters
  /// rather than slices because slices are not one size — a loose list or
  /// an indented block will not be cut at a blank line (see
  /// [_splitSlices]) and so grows past the target — and a frame that built
  /// a fixed count of those would build several frames' worth at once.
  /// Whatever a single slice costs, one lands in the frame regardless, so
  /// the page never stalls behind a budget no slice can fit.
  static const _revealBudget = _sliceTarget * 2;

  /// A line that could be a reference definition, `[label]: destination`.
  /// A document carrying one anywhere does not open in slices at all — see
  /// [_splitSlices] for why that is the honest answer rather than a
  /// relocation of them.
  static final RegExp _referenceDefinition = RegExp(
    r'^ {0,3}\[[^\[\]\n]+\]:',
  );

  /// A line that starts an item of a list at the list's own top level —
  /// column zero, so a nested item can never be mistaken for a boundary.
  /// This is the secondary cut for lists that grow past the target without
  /// a blank line between their items; see [_splitSlices].
  static final RegExp _topLevelItem = RegExp(
    r'^(?:[-*+]|\d{1,9}[.)])[ \t]+',
  );

  /// The opening or closing of a fenced block. Content between a pair is
  /// never a boundary, so a fence stays whole inside one slice.
  static final RegExp _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');

  void _prepare() {
    final text = widget.text;
    final markdown = widget.markdown;
    if (_preparedFor == text && _preparedMarkdown == markdown) return;
    _preparedFor = text;
    _preparedMarkdown = markdown;
    final lines = text.split('\n');
    // Code units are the cheap fence: when they fit inside the fold, the
    // characters do too, and a document need not pay a per-grapheme walk to
    // learn it is short.
    _long = text.length > _foldCharacters
        ? text.characters.length > _foldCharacters || lines.length > _foldLines
        : lines.length > _foldLines;
    final firstPage = lines.take(_foldLines).join('\n');
    _foldedText = _long
        ? '${firstPage.characters.take(_foldCharacters)}…'
        : text;
    _sliceTexts = _splitSlices(text);
    _sliceWidgets.clear();
    _sliceMarkdown = widget.markdown ?? nexLooksLikeMarkdown(text);
    _sliceDirection = nexDirectionOf(text);
    // An edit that arrived while the page was open shows in full at once:
    // this page grew by hand once already.
    _revealed = expanded ? _sliceTexts.length : 0;
  }

  /// Cuts [source] into slices at boundaries between top-level blocks —
  /// never inside one — so that what a slice renders is what those blocks
  /// rendered inside the one document. A blank line is the boundary
  /// Markdown itself uses between paragraphs, tables, fences and quotes.
  ///
  /// Four things refuse to be sliced, and each keeps the whole document in
  /// one piece rather than be drawn differently from how it is today:
  ///
  /// * A document with a reference definition in it — `[label]: destination`
  ///   anywhere. Definitions are document-level facts in Markdown, usable
  ///   from anywhere and invisible wherever they sit, so a slice boundary
  ///   could strand one where the link that references it cannot see it.
  ///   Splitting them out and re-reading them in front of every slice is
  ///   the fix that would keep the links working, and it is not taken:
  ///   guessing at the parser's exact idea of a definition, and being
  ///   wrong, would duplicate a line the reader never meant to show. One
  ///   unsliced document costs a pause; a duplicated one costs trust.
  /// * A run of lines with no blank line in it past the secondary cut
  ///   below — a paragraph is never cut mid-sentence, so a single unbroken
  ///   paragraph of any size stays one slice.
  /// * A fenced block, however long: half a fence is not a code sample.
  /// * A loose list's own blank lines, and an indented block's — the cut
  ///   waits for a boundary the list or the block is not in the middle of
  ///   (see the guard below, and the ceiling above it).
  static List<String> _splitSlices(String source) {
    if (source.length <= _sliceOnlyAbove) return [source];
    // Preserve an intentional whitespace-only note as one exact slice.
    if (source.trim().isEmpty) return [source];
    // A document that could be carrying reference definitions opens whole.
    final lines = source.split('\n');
    for (final line in lines) {
      if (_referenceDefinition.hasMatch(line)) return [source];
    }
    // For every line, the nearest later line that has content on it — where
    // the blank run it may start comes to an end — known in one backward
    // walk, so the guard on the cut below costs nothing per candidate
    // however long the run.
    final nextContent = List<int>.filled(lines.length, -1);
    var upcoming = -1;
    for (var i = lines.length - 1; i >= 0; i--) {
      nextContent[i] = upcoming;
      if (lines[i].trim().isNotEmpty) upcoming = i;
    }
    final slices = <String>[];
    final slice = StringBuffer();
    var fence = '';
    void cut() {
      // Do not trim: the document's leading/trailing whitespace and blank
      // lines between blocks must survive slicing unchanged.
      final text = slice.toString();
      if (text.isNotEmpty) slices.add(text);
      slice.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // A fence line is recognised before anything else, so that a blank
      // line inside a fence is content and never a boundary.
      final markerMatch = _fence.firstMatch(line);
      final marker = markerMatch?.group(1);
      final opening = fence.isEmpty && marker != null;
      // A closing fence must use the opening marker's character, have at
      // least as many markers, and end with whitespace only. Three ticks
      // inside a four-tick fence are content, not the end of the block.
      final closing =
          fence.isNotEmpty &&
          marker != null &&
          marker[0] == fence[0] &&
          marker.length >= fence.length &&
          line.substring(markerMatch!.end).trim().isEmpty;
      if (opening) {
        fence = marker!;
      } else if (closing) {
        fence = '';
      }
      // A list with no blank lines between its items grows past the target
      // without ever meeting one. Past a harder ceiling the cut falls
      // between items instead: the line about to be written starts an item
      // of the list's own top level — the one place a line boundary is a
      // block boundary for sure, because the item line starts a block of
      // its own. The item is not yet written, so the next slice starts with
      // it rather than ending the last one inside it.
      if (!opening &&
          !closing &&
          fence.isEmpty &&
          slice.length >= _sliceTarget * 3 &&
          _topLevelItem.hasMatch(line)) {
        cut();
      }
      slice.write(line);
      if (i < lines.length - 1) slice.write('\n');
      // A blank line between top-level blocks, past the target size: the
      // boundary Markdown itself would have drawn — unless the blank run
      // ends in the middle of something. An indented line after a blank is
      // the inside of an indented code block or a list item's own
      // continuation paragraph; a column-zero item is the next item of a
      // loose list. Cutting at either would open the next slice in the
      // middle of a block — a second list where the document has one, a
      // stray paragraph where it has an item's — so both wait for the
      // ceiling above, and a slice begins only at a block that truly
      // starts at column zero.
      final after = nextContent[i];
      final follows = after >= 0 ? lines[after] : '';
      if (fence.isEmpty &&
          line.trim().isEmpty &&
          slice.length >= _sliceTarget &&
          !follows.startsWith(' ') &&
          !follows.startsWith('\t') &&
          !_topLevelItem.hasMatch(follows)) {
        cut();
      }
    }
    cut();
    // Every input, including intentional whitespace, retains at least one
    // slice. The early whitespace guard also avoids many empty layers.
    if (slices.isEmpty) return [source];
    return slices;
  }

  /// Reveals more of the opened page after the frame the current slices are
  /// built in, until the page is whole.
  void _revealNextFrame() {
    if (!mounted || !expanded || _revealed >= _sliceTexts.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The text — or the fold — may have changed between scheduling and
      // firing; the count answers for itself before anything is indexed.
      if (!mounted || !expanded || _revealed >= _sliceTexts.length) return;
      setState(() {
        // At least one slice lands whatever it costs — a page waiting on
        // one big slice is not waiting at all — and the rest of the frame's
        // budget is spent on whole slices until it runs out: counting
        // slices instead would let two oversized ones spend three frames'
        // worth of building in one.
        var budget = _revealBudget;
        do {
          budget -= _sliceTexts[_revealed].length;
          _revealed++;
        } while (_revealed < _sliceTexts.length && budget > 0);
      });
      _revealNextFrame();
    });
  }

  Widget _slice(int index) {
    while (_sliceWidgets.length <= index) {
      final i = _sliceWidgets.length;
      _sliceWidgets.add(_ExpandedSlice(
        text: _sliceTexts[i],
        markdown: _sliceMarkdown,
        direction: _sliceDirection,
        onTapLink: widget.onTapLink,
        onHoldLink: widget.onHoldLink,
        onCopyCode: widget.onCopyCode,
      ));
    }
    return _sliceWidgets[index];
  }

  /// The folded first page, or a document short enough to have none — one
  /// body, exactly as this widget always drew it.
  Widget _singleBody(BuildContext context, String text) {
    if (widget.contentBuilder != null) {
      return widget.contentBuilder!(context, text);
    }
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.62);
    return NexSelectionArea(
      levelHighlight: true,
      child: (widget.markdown ?? nexLooksLikeMarkdown(text))
          ? NexMarkdown(
              text,
              selectable: false,
              preserveLineBreaks: true,
              onTapLink: widget.onTapLink,
              onHoldLink: widget.onHoldLink,
              onCopyCode: widget.onCopyCode,
              style: style,
            )
          : NexLinkText(
              text,
              onTapLink: widget.onTapLink,
              onHoldLink: widget.onHoldLink,
              style: style,
              selectable: false,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _prepare();
    final Widget body;
    if (!expanded || !_long) {
      body = _singleBody(context, _long ? _foldedText : widget.text);
    } else if (widget.contentBuilder != null) {
      // Source code is one block that scrolls sideways; slicing it into
      // several would give each its own scrollbar and its own border. One
      // boundary at least keeps the rest of the sheet cheap to composite
      // over it once it is laid out.
      body = RepaintBoundary(
        child: widget.contentBuilder!(context, widget.text),
      );
    } else {
      body = _singlePage();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        body,
        if (_long)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _moreButton(context),
          ),
      ],
    );
  }

  /// The opened page: the slices revealed so far, under the one selection
  /// area the whole document has always shared.
  Widget _singlePage() => NexSelectionArea(
    levelHighlight: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (var i = 0; i < _revealed; i++) _slice(i)],
    ),
  );

  Widget _moreButton(BuildContext context) => TextButton.icon(
    onPressed: () {
      setState(() {
        if (expanded) {
          expanded = false;
          // Back to nothing revealed, so the next opening is paced as well:
          // a retained full count would rebuild the whole document in one
          // frame on the second More.
          _revealed = 0;
        } else {
          expanded = true;
          // One slice in the tap's own frame: the page is visibly open the
          // moment the tap lands, and the rest arrives over the frames that
          // follow.
          _revealed = 1;
        }
      });
      _revealNextFrame();
    },
    icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
    label: Text(
      expanded
          ? nexLabel(context, 'Less', 'کمتر')
          : nexLabel(context, 'More', 'بیشتر'),
    ),
  );
}

/// One slice of an opened page: built once, kept, and given its own layer.
///
/// The identical widget instance is what makes revealing the next slice
/// cheap — a child whose widget has not changed is not rebuilt — and the
/// [RepaintBoundary] is what makes everything after the reveal cheap:
/// scrolling the page, or opening a sheet over it, moves cached layers
/// instead of re-recording a picture the size of the whole document. The
/// theme is read here rather than captured above so that a theme change
/// still reaches text that was built frames ago.
class _ExpandedSlice extends StatelessWidget {
  const _ExpandedSlice({
    required this.text,
    required this.markdown,
    required this.direction,
    this.onTapLink,
    this.onHoldLink,
    this.onCopyCode,
  });

  final String text;
  final bool markdown;
  final TextDirection? direction;
  final void Function(String)? onTapLink;
  final NexLinkHold? onHoldLink;
  final void Function(String)? onCopyCode;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.62);
    return RepaintBoundary(
      child: markdown
          ? NexMarkdown(
              text,
              selectable: false,
              preserveLineBreaks: true,
              direction: direction,
              onTapLink: onTapLink,
              onHoldLink: onHoldLink,
              onCopyCode: onCopyCode,
              style: style,
            )
          : NexLinkText(
              text,
              onTapLink: onTapLink,
              onHoldLink: onHoldLink,
              style: style,
              selectable: false,
            ),
    );
  }
}
