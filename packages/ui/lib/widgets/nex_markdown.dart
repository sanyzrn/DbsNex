import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../tokens/nex_text_direction.dart';
import 'nex_selectable_lines.dart';
import 'nex_link_text.dart';
import 'nex_selection_menu.dart';
import '../tokens/nex_contrast.dart';
import '../tokens/nex_tokens.dart';

/// Markdown, rendered the way the rest of Nex renders the user's own writing.
///
/// This exists because two different things in Nex are already Markdown and
/// were being shown as if they were not: a `.md` file someone shares into the
/// app, and every answer the assistant writes. A model asked for a list
/// produces one; without this the user reads the asterisks.
///
/// ## Direction
///
/// `flutter_markdown_plus` takes its direction from the ambient
/// [Directionality] — which is the interface language, and in this app the
/// interface language is not what decides. A Persian document read while the
/// app is in English would otherwise come out left-aligned with its bullets on
/// the wrong side: correct glyphs, wrong page. So the direction is derived
/// from the text and imposed here.
///
/// **Each block decides for itself** (2.9.1). A heading, a paragraph, a list
/// item, a blockquote and a table cell are separate things to read, and each
/// is laid out in the direction its own words are mostly written in
/// ([nexDominantDirectionOf]) — so a Persian paragraph that opens with an
/// English product name stays right to left, while an English paragraph in the
/// same document stays left to right. Fenced code is always left to right.
///
/// The document still has one direction of its own, used for the things that
/// are layout rather than text — a list's bullet column, a blockquote's rule —
/// and it is chosen the same way, by what dominates the document. Callers that
/// render one document as several bodies may pass that direction in
/// ([direction]), and it is also the fallback for a block whose words carry no
/// direction at all: a line of numbers, a table of dates.
///
/// ## Styling
///
/// Derived from the app's own theme rather than the package's defaults, and
/// deliberately quieter than the web's. A heading inside a note is a heading
/// within a page that is itself small — `h1` at browser scale turns a
/// three-line note into a poster. So the ramp is compressed, and the body text
/// keeps the same size and line height it has everywhere else in the app.
class NexMarkdown extends StatefulWidget {
  const NexMarkdown(
    this.text, {
    super.key,
    this.style,
    this.direction,
    this.onTapLink,
    this.onHoldLink,
    this.onCopyCode,
    this.selectable = true,
    this.preserveLineBreaks = false,
  });

  /// The raw Markdown source.
  final String text;

  /// The direction the document reads in, when the caller has already decided.
  ///
  /// Null — the default, and every caller until long documents began to be
  /// opened in slices — is derived from the text itself, as documented on
  /// this class. A caller that renders one document as several bodies passes
  /// the whole document's direction here, so a block with no strong letters of
  /// its own keeps the page's direction instead of flipping the slice that
  /// happens to hold it.
  ///
  /// This is the fallback, not an override: a block whose own words decide a
  /// direction still takes it. That is what lets one Persian document hold an
  /// English code sample's introduction and a Persian note around it.
  final TextDirection? direction;

  /// Base style for paragraph text. Defaults to `bodyLarge`, matching
  /// [NexTextSurface] so a rendered note and a plain one read as the same app.
  final TextStyle? style;

  /// Called with a link's destination. Null leaves links inert — which is the
  /// right default for a package that has no business launching a browser;
  /// the app passes a handler where opening one makes sense.
  final void Function(String href)? onTapLink;

  /// Link-specific actions, without selecting the surrounding text.
  final NexLinkHold? onHoldLink;

  /// Called with the contents of an inline `code` span when one is tapped.
  ///
  /// Null leaves code spans inert, which is the right default for a package
  /// with no clipboard and no words of its own to say afterwards — copying
  /// silently is indistinguishable from a tap that missed. A caller that can
  /// say something passes a handler.
  ///
  /// Inline spans only. A fenced block already scrolls, and turning one into a
  /// single tap target would take that away.
  final void Function(String code)? onCopyCode;

  /// Whether this block brings its own selection.
  ///
  /// True wraps it in a [SelectionArea]. It used to mean `selectable: true` on
  /// the markdown body, which is a `SelectableText` underneath, and that
  /// carried two costs: a `SelectableText` handles every gesture itself and
  /// never dispatches a [TextSpan.recognizer], so a link or a code span in the
  /// same paragraph stopped answering a tap — and its menu is Flutter's
  /// default one, which carries every other app's `ACTION_PROCESS_TEXT`
  /// entry. Callers that wanted both worked around it by wrapping this in an
  /// area themselves and passing false; doing it here means nobody has to
  /// know that, and the menu is the app's own either way.
  ///
  /// False is for a caller that already owns a [SelectionArea] — the note
  /// detail sheet and the assistant's thread both do, because the area has to
  /// reach wider than this one block.
  final bool selectable;

  /// Keep a note's typed Enter even when inline formatting enables Markdown.
  /// Assistant replies and imported Markdown keep CommonMark's soft wrapping.
  final bool preserveLineBreaks;

  @override
  State<NexMarkdown> createState() => _NexMarkdownState();
}

/// The tag a block's inline runs are wrapped in before they are visited.
///
/// A synthetic inline element rather than a real Markdown tag: it exists only
/// long enough for the renderer to hand one run of words to the direction
/// builder, and the block it lands in — its padding, bullet, rule, cell, or
/// nested list — stays the package's.
const _textTag = 'nex-text';

/// The block tags whose inline runs read as text and choose a direction.
const _wrappedBlocks = <String>[
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'blockquote',
];

/// Tags that are structure, not words, inside a list item or a blockquote.
///
/// A run of inline text ends at one of these; the package still renders it as
/// the block it is, so a nested list or a code fence keeps its own layout.
const _blockTags = <String>{
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'blockquote',
  'ul',
  'ol',
  'pre',
  'table',
  'thead',
  'tbody',
  'tr',
  'hr',
  'section',
};

/// Stateful only so that something owns the tap recognizers the link and
/// code-span builders hand out. Nothing here is state the user can see.
class _NexMarkdownState extends State<NexMarkdown> {
  final _codeSpans = _NexCodeSpanBuilder();
  final _links = NexLinkRecognizers();
  final _blocks = _NexDirectionalBlockBuilder();

  @override
  void dispose() {
    _codeSpans.dispose();
    _links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.text;
    final direction =
        widget.direction ??
        nexDominantDirectionOf(text) ??
        Directionality.of(context);
    _codeSpans.onTap = widget.onCopyCode;
    _links
      ..onTap = widget.onTapLink
      ..onHold = widget.onHoldLink;
    final sheet =
        _sheet(
          theme,
          widget.style ?? theme.textTheme.bodyLarge,
          direction,
        ).copyWith(
          // The renderer scrolls intrinsic tables on their own horizontal axis.
          // Cap long cells so a paragraph does not become one enormous column.
          tableColumnWidth: _NexMarkdownColumnWidth(
            MediaQuery.textScalerOf(context).scale(320),
          ),
          tableScrollbarThumbVisibility: true,
        );
    _blocks
      ..styleSheet = sheet
      ..documentDirection = direction
      ..preserveLineBreaks = widget.preserveLineBreaks
      ..links = _links
      ..codeSpans = _codeSpans;
    // Every paragraph, heading and list item is its own text widget, so a
    // copy across them needs its line breaks put back — see
    // [NexSelectableLines].
    final body = NexSelectableLines(
      child: Directionality(
        textDirection: direction,
        child: MarkdownBody(
          data: text,
          softLineBreak: widget.preserveLineBreaks,
          // Never the markdown body's own selection: it is a `SelectableText`,
          // which eats the taps the code spans and links are built on. The area
          // below does it without taking anything away — see [selectable].
          selectable: false,
          fitContent: false,
          builders: {
            // Code fences always use LTR, independently of the document.
            // All prose, list and inline-code directions stay untouched.
            'pre': _NexFencedCodeBuilder(
              style: sheet.code,
              padding: sheet.codeblockPadding,
            ),
            // Registered for their `visitElementBefore` only, which wraps
            // each block's inline runs in [_textTag] before the renderer
            // reaches them. The blocks themselves stay the package's — its
            // own cell hook, for instance, is an inline branch that would
            // drop the `TableCell` and leave a row empty.
            for (final tag in [..._wrappedBlocks, 'table']) tag: _blocks,
            _textTag: _blocks,
          },
          styleSheet: sheet,
          onTapLink: widget.onTapLink == null
              ? null
              : (_, href, _) {
                  if (href != null && href.isNotEmpty) widget.onTapLink!(href);
                },
        ),
      ),
    );
    return widget.selectable ? NexSelectionArea(child: body) : body;
  }

  MarkdownStyleSheet _sheet(
    ThemeData theme,
    TextStyle? body,
    TextDirection direction,
  ) {
    final scheme = theme.colorScheme;
    final link = nexReadableOn(scheme.primary, scheme.surface);
    final base = (body ?? const TextStyle()).copyWith(height: 1.5);
    // Monospace by family name rather than by a bundled font: the app ships
    // one typeface for its own text, and a code span that falls back to the
    // platform's mono is closer to right than one set in the body face.
    final mono = base.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier New', 'monospace'],
      fontSize: (base.fontSize ?? 16) - 1,
    );
    TextStyle heading(double size, FontWeight weight) =>
        base.copyWith(fontSize: size, fontWeight: weight, height: 1.3);

    final fontSize = base.fontSize ?? 16;
    return MarkdownStyleSheet(
      p: base,
      pPadding: const EdgeInsets.only(bottom: NexSpacing.xs),
      // Four steps, not six, and the top of the ramp is only a little larger
      // than the body. See the class comment.
      h1: heading(fontSize + 6, FontWeight.w700),
      h2: heading(fontSize + 3, FontWeight.w700),
      h3: heading(fontSize + 1, FontWeight.w600),
      h4: heading(fontSize, FontWeight.w600),
      h5: heading(fontSize, FontWeight.w600),
      h6: heading(fontSize, FontWeight.w600),
      h1Padding: const EdgeInsets.only(top: NexSpacing.sm),
      h2Padding: const EdgeInsets.only(top: NexSpacing.sm),
      h3Padding: const EdgeInsets.only(top: NexSpacing.xs),
      em: base.copyWith(fontStyle: FontStyle.italic),
      strong: base.copyWith(fontWeight: FontWeight.w700),
      del: base.copyWith(decoration: TextDecoration.lineThrough),
      // Link text is text: the accent darkened or lightened to 4.5:1 on the
      // page where it falls short (LOC-07), unchanged where it does not.
      a: base.copyWith(
        color: link,
        decoration: TextDecoration.underline,
        decorationColor: link.withValues(alpha: 0.5),
      ),
      code: mono.copyWith(backgroundColor: scheme.surfaceContainerHighest),
      codeblockPadding: const EdgeInsets.all(NexSpacing.sm),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      blockquote: base.copyWith(color: scheme.onSurfaceVariant),
      // `EdgeInsetsDirectional` is not accepted here — the package's fields
      // are plain `EdgeInsets` — so the leading edge is resolved by hand
      // against the direction this document turned out to be.
      blockquotePadding: EdgeInsets.only(
        left: direction == TextDirection.rtl ? 0 : NexSpacing.sm,
        right: direction == TextDirection.rtl ? NexSpacing.sm : 0,
        top: NexSpacing.xs,
        bottom: NexSpacing.xs,
      ),
      // A bar on the leading edge, which follows the text's direction rather
      // than the interface's — the whole subtree is already flipped above.
      blockquoteDecoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: scheme.outlineVariant, width: 3),
        ),
      ),
      listBullet: base,
      listIndent: NexSpacing.lg,
      blockSpacing: NexSpacing.sm,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      tableHead: base.copyWith(fontWeight: FontWeight.w700),
      tableBody: base,
      tableBorder: TableBorder.all(color: scheme.outlineVariant, width: 1),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.sm,
        vertical: NexSpacing.xs,
      ),
      checkbox: base.copyWith(color: scheme.primary),
    );
  }
}

/// Fenced and indented code must be left-to-right even in a Persian document.
/// Only the pre block is overridden; the Markdown package retains its outer
/// code-block decoration, and text outside the block keeps its direction.
class _NexFencedCodeBuilder extends MarkdownElementBuilder {
  _NexFencedCodeBuilder({required this.style, required this.padding});

  final TextStyle? style;
  final EdgeInsets? padding;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // Match the package's formatter: remove the terminal fence newline,
    // never indentation, intentional blank lines or internal whitespace.
    final code = element.textContent.replaceFirst(RegExp(r'\n$'), '');
    return _NexFencedCode(
      code: code,
      style: style,
      padding: padding ?? EdgeInsets.zero,
    );
  }
}

/// Builds each run of block text in the direction its own words are mostly
/// written in.
///
/// The package takes one direction for the whole document from the ambient
/// [Directionality], and it builds a block's inline runs itself, so there is
/// no point at which a paragraph can be handed a direction other than the
/// document's. This builder wraps every block's inline runs in a synthetic
/// element before the renderer visits them; when that element closes, its
/// words are built here — with the same styles, link recognizers, inline-code
/// taps and images the package would have used — as a [Text] under a
/// [Directionality] of its own.
///
/// The block is still the package's, not a replacement for it: a paragraph
/// keeps its padding, a list item its bullet and nested list, a blockquote its
/// rule, a table cell its border and sizing. Only the reading direction of the
/// words is local, which is what makes it safe in a document whose structure
/// the renderer already got right.
class _NexDirectionalBlockBuilder extends MarkdownElementBuilder {
  MarkdownStyleSheet? styleSheet;
  TextDirection? documentDirection;
  bool preserveLineBreaks = false;
  NexLinkRecognizers? links;
  _NexCodeSpanBuilder? codeSpans;

  static final _softBreak = RegExp(r' ?\n *');
  static final _leadingSpaces = RegExp(r'^ *');

  @override
  void visitElementBefore(md.Element element) {
    if (element.tag == 'table') {
      _cellsOf(element);
    } else if (_wrappedBlocks.contains(element.tag)) {
      _wrapRuns(element);
    }
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final sheet = styleSheet;
    if (sheet == null || element.tag != _textTag) return null;
    return _textRun(context, element, preferredStyle, parentStyle, sheet);
  }

  /// Every table cell, however deeply its section and rows nest it.
  void _cellsOf(md.Node node) {
    if (node is! md.Element) return;
    if (node.tag == 'th' || node.tag == 'td') {
      _wrapRuns(node);
      return;
    }
    for (final child in node.children ?? const <md.Node>[]) {
      _cellsOf(child);
    }
  }

  /// Wraps each run of inline content in [block] in a [_textTag] element.
  ///
  /// Runs are split at structure — a nested list, a code fence, a nested
  /// paragraph, a task list's checkbox — so the package still lays those out
  /// as the blocks they are. The tree has not been visited yet when a block is
  /// entered, so this changes the parse of this build, not anything already
  /// rendered.
  void _wrapRuns(md.Element block) {
    final children = block.children;
    if (children == null || children.isEmpty) return;
    final out = <md.Node>[];
    var run = <md.Node>[];
    var trimNext = block.tag == 'p' || block.tag == 'li';

    void flush() {
      if (run.isEmpty) return;
      final wrapper = md.Element(_textTag, List.of(run));
      final cell = block.tag == 'th' || block.tag == 'td';
      if (cell) {
        wrapper.attributes['header'] = block.tag == 'th' ? '1' : '0';
        final align = block.attributes['align'];
        if (align != null) wrapper.attributes['align'] = align;
      }
      if (trimNext) {
        wrapper.attributes['trim'] = '1';
        trimNext = false;
      }
      out.add(wrapper);
      run = <md.Node>[];
    }

    for (final node in children) {
      final checkbox =
          node is md.Element &&
          node.tag == 'input' &&
          node.attributes['type'] == 'checkbox';
      if (node is md.Element && (_blockTags.contains(node.tag) || checkbox)) {
        flush();
        out.add(node);
      } else {
        run.add(node);
      }
    }
    flush();
    children
      ..clear()
      ..addAll(out);
  }

  /// One run of block text, in its own direction.
  ///
  /// The package still adds the paragraph's padding, the cell's border and
  /// padding, the list item's bullet and the blockquote's rule; this fills the
  /// width it is given and aligns the words to their own leading edge, so a
  /// short Persian line reaches the right side of the page it sits on.
  Widget? _textRun(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
    MarkdownStyleSheet sheet,
  ) {
    final header = element.attributes['header'];
    final base = header == null
        ? (preferredStyle ?? parentStyle ?? sheet.p)
        : (header == '1' ? sheet.tableHead : sheet.tableBody);
    final spans = _spans(
      element.children ?? const <md.Node>[],
      base,
      sheet,
      trimLeading: element.attributes['trim'] == '1',
    );
    if (spans.isEmpty) return null;
    final direction =
        nexDominantDirectionOf(element.textContent) ??
        documentDirection ??
        Directionality.of(context);
    final align = _cellAlign(element);
    final text = Text.rich(
      TextSpan(children: spans),
      style: base,
      textDirection: direction,
      textAlign: align,
      // The package forces a strut so a bold word inside a paragraph cannot
      // change that paragraph's line height. Keep it, with the run's own
      // base style, or a rendered note's lines would move against a plain one.
      strutStyle: base == null
          ? null
          : StrutStyle(
              fontFamily: base.fontFamily,
              fontSize: base.fontSize,
              height: base.height,
              leading: 0,
              forceStrutHeight: true,
            ),
    );
    // Aligned to its own edge rather than stretched: a short right-to-left
    // line has to reach the right edge of the page it sits on, but a `Text`
    // drawn the full width of the row would also answer taps in the empty
    // half beside its words. The `Align` takes the row's width and the text
    // keeps its own, so the glyphs are both placed and touchable where they
    // read.
    return Directionality(
      textDirection: direction,
      child: Align(
        alignment: switch (align) {
          TextAlign.center => Alignment.center,
          TextAlign.left => Alignment.centerLeft,
          TextAlign.right => Alignment.centerRight,
          _ =>
            direction == TextDirection.rtl
                ? Alignment.centerRight
                : Alignment.centerLeft,
        },
        child: text,
      ),
    );
  }

  /// The inline spans of [element], built once, in the block's style.
  ///
  /// Anything the package can draw as text is handled here: styled leaves,
  /// links with their recognizers, inline code with its tap, line breaks,
  /// superscripts and images. A task list's `input` is skipped, because the
  /// renderer draws that checkbox as the list's bullet.
  List<InlineSpan> _spans(
    Iterable<md.Node> nodes,
    TextStyle? style,
    MarkdownStyleSheet sheet, {
    bool trimLeading = false,
    GestureRecognizer? recognizer,
  }) {
    final spans = <InlineSpan>[];
    var first = trimLeading;
    void addText(String text) {
      if (first) {
        text = text.replaceFirst(_leadingSpaces, '');
        first = false;
      }
      if (text.isEmpty) return;
      spans.add(
        TextSpan(
          text: text,
          style: style,
          recognizer: recognizer,
          mouseCursor: recognizer == null ? null : SystemMouseCursors.click,
        ),
      );
    }

    for (final node in nodes) {
      if (node is md.Text) {
        addText(
          preserveLineBreaks
              ? node.text
              : node.text.replaceAll(_softBreak, ' '),
        );
        continue;
      }
      if (node is! md.Element) continue;
      final children = node.children ?? const <md.Node>[];
      switch (node.tag) {
        case 'br':
          spans.add(const TextSpan(text: '\n'));
          first = true;
          break;
        case 'strong':
          spans.addAll(
            _spans(
              children,
              style?.merge(sheet.strong) ?? sheet.strong,
              sheet,
              recognizer: recognizer,
            ),
          );
          break;
        case 'em':
          spans.addAll(
            _spans(
              children,
              style?.merge(sheet.em) ?? sheet.em,
              sheet,
              recognizer: recognizer,
            ),
          );
          break;
        case 'del':
          spans.addAll(
            _spans(
              children,
              style?.merge(sheet.del) ?? sheet.del,
              sheet,
              recognizer: recognizer,
            ),
          );
          break;
        case 'code':
          final code = node.textContent;
          final codeStyle = style?.merge(sheet.code) ?? sheet.code;
          // A link's own gesture wins: a code span inside a link is still the
          // link, and its menu is the link's.
          final tap = recognizer == null && !code.contains('\n')
              ? codeSpans?.recognizerFor(code)
              : null;
          spans.add(
            TextSpan(
              text: code,
              style: codeStyle,
              recognizer: tap,
              mouseCursor: tap == null ? null : SystemMouseCursors.click,
            ),
          );
          break;
        case 'a':
          final href = node.attributes['href'];
          final hasHref = href != null && href.isNotEmpty;
          final linkStyle = hasHref ? style?.merge(sheet.a) ?? sheet.a : style;
          final link = !hasHref || recognizer != null
              ? recognizer
              : links?.forHref(href);
          spans.addAll(_spans(children, linkStyle, sheet, recognizer: link));
          break;
        case 'img':
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _image(node.attributes['src'] ?? ''),
            ),
          );
          break;
        case 'sup':
          spans.add(
            TextSpan(
              text: node.textContent,
              style: (style ?? const TextStyle()).copyWith(
                fontFeatures: const [FontFeature.enable('sups')],
              ),
              recognizer: recognizer,
            ),
          );
          break;
        case 'input':
          // The task list's checkbox: the renderer draws it as the bullet of
          // the list item, and drawing it again would show it twice.
          break;
        default:
          spans.addAll(_spans(children, style, sheet, recognizer: recognizer));
          break;
      }
    }
    return spans;
  }

  /// A cell's own alignment, when the document asks for one; otherwise the
  /// cell's direction's start edge.
  TextAlign _cellAlign(md.Element element) =>
      switch (element.attributes['align']) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'left' => TextAlign.left,
        _ => TextAlign.start,
      };

  /// An inline image, drawn with the same sources the renderer accepts:
  /// network, bundled asset, and an embedded data URI. A relative or local
  /// file path is not resolvable here — the app's Markdown is read from a
  /// note or a model, neither of which carries a base directory — so it draws
  /// nothing rather than a broken box.
  Widget _image(String source) {
    final parts = source.split('#');
    if (parts.isEmpty) return const SizedBox();
    double? width;
    double? height;
    if (parts.length == 2) {
      final dimensions = parts.last.split('x');
      if (dimensions.length == 2) {
        width = double.tryParse(dimensions[0]);
        height = double.tryParse(dimensions[1]);
      }
    }
    final uri = Uri.tryParse(parts.first);
    if (uri == null) return const SizedBox();
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return Image.network(
        uri.toString(),
        width: width,
        height: height,
        errorBuilder: _noImage,
      );
    }
    if (uri.scheme == 'resource') {
      return Image.asset(
        uri.path,
        width: width,
        height: height,
        errorBuilder: _noImage,
      );
    }
    if (uri.scheme == 'data') {
      try {
        return Image.memory(
          uri.data!.contentAsBytes(),
          width: width,
          height: height,
          errorBuilder: _noImage,
        );
      } on Object {
        return const SizedBox();
      }
    }
    return const SizedBox();
  }

  static Widget _noImage(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) => const SizedBox();
}

/// Keep the code's horizontal scrollbar independent of the RTL page scroll.
class _NexFencedCode extends StatefulWidget {
  const _NexFencedCode({
    required this.code,
    required this.style,
    required this.padding,
  });

  final String code;
  final TextStyle? style;
  final EdgeInsets padding;

  @override
  State<_NexFencedCode> createState() => _NexFencedCodeState();
}

class _NexFencedCodeState extends State<_NexFencedCode> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: widget.padding,
        child: Text(
          widget.code,
          style: widget.style,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          softWrap: false,
        ),
      ),
    ),
  );
}

class _NexMarkdownColumnWidth extends IntrinsicColumnWidth {
  const _NexMarkdownColumnWidth(this.maximum);
  final double maximum;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      super
          .minIntrinsicWidth(cells, containerWidth)
          .clamp(0.0, maximum)
          .toDouble();

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      super
          .maxIntrinsicWidth(cells, containerWidth)
          .clamp(0.0, maximum)
          .toDouble();
}

/// Hands out one tap recognizer per inline `code` span, released with the
/// widget.
///
/// Only on dispose, not per rebuild: a recognizer is still attached to spans
/// in the tree that produced it, and a re-parse (this renderer re-parses on a
/// dependency change as well as a rebuild) would otherwise dispose one still
/// in use. The cost is a handful of small objects per rebuild of a sheet that
/// rebuilds a handful of times before it closes.
class _NexCodeSpanBuilder {
  /// Set by the widget on every build; null until it has been.
  void Function(String code)? onTap;

  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  /// A recognizer for a tap on [code], or null when code spans are inert.
  TapGestureRecognizer? recognizerFor(String code) {
    final handler = onTap;
    if (handler == null || code.isEmpty || code.contains('\n')) return null;
    final recognizer = TapGestureRecognizer()..onTap = () => handler(code);
    _recognizers.add(recognizer);
    return recognizer;
  }

  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }
}
