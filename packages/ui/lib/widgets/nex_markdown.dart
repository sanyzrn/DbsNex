import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../tokens/nex_text_direction.dart';
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
/// The same rule as [NexBodyText], and the reason this is a widget rather than
/// a call to `MarkdownBody` at each site. `flutter_markdown_plus` takes its
/// direction from the ambient [Directionality] — which is the interface
/// language, and in this app the interface language is not what decides. A
/// Persian document read while the app is in English would otherwise come out
/// left-aligned with its bullets on the wrong side: correct glyphs, wrong page.
/// So the direction is derived from the text and imposed here.
///
/// That is a whole-document decision, and it is the honest limit of this
/// widget: a file whose paragraphs alternate between Persian and English gets
/// one direction for all of them, chosen by whichever script dominates. Every
/// renderer surveyed either did the same thing or ignored the ambient
/// direction entirely, and per-block direction is a larger piece of work than
/// the problem has so far earned.
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
    this.onTapLink,
    this.onCopyCode,
    this.selectable = true,
  });

  /// The raw Markdown source.
  final String text;

  /// Base style for paragraph text. Defaults to `bodyLarge`, matching
  /// [NexBodyText] so a rendered note and a plain one read as the same app.
  final TextStyle? style;

  /// Called with a link's destination. Null leaves links inert — which is the
  /// right default for a package that has no business launching a browser;
  /// the app passes a handler where opening one makes sense.
  final void Function(String href)? onTapLink;

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

  /// Whether the rendered text can be selected *by this widget*.
  ///
  /// True here means `SelectableText`, and that carries a cost worth knowing
  /// about: `SelectableText` handles every gesture itself and never dispatches
  /// a [TextSpan.recognizer], so a link — or a code span — inside one cannot
  /// be tapped at all. A caller that needs both selection and taps wraps this
  /// in a [SelectionArea] and passes false: selection then belongs to the area
  /// and the spans keep their gestures.
  ///
  /// False is also right in the assistant's thread, where selection inside a
  /// scrolling list fights the scroll gesture and hands the user a partial
  /// paste — that surface copies a whole message on long-press instead, and a
  /// selectable child would swallow the long-press before it arrives.
  final bool selectable;

  @override
  State<NexMarkdown> createState() => _NexMarkdownState();
}

/// Stateful only so that something owns the tap recognizers the code-span
/// builder hands out. Nothing here is state the user can see.
class _NexMarkdownState extends State<NexMarkdown> {
  final _NexCodeSpanBuilder _codeSpans = _NexCodeSpanBuilder();

  @override
  void dispose() {
    _codeSpans.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.text;
    final direction = nexDirectionOf(text) ?? Directionality.of(context);
    _codeSpans.onTap = widget.onCopyCode;
    return Directionality(
      textDirection: direction,
      child: MarkdownBody(
        data: text,
        selectable: widget.selectable,
        fitContent: false,
        builders: {if (widget.onCopyCode != null) 'code': _codeSpans},
        styleSheet: _sheet(
          theme,
          widget.style ?? theme.textTheme.bodyLarge,
          direction,
        ),
        onTapLink: widget.onTapLink == null
            ? null
            : (_, href, _) {
                if (href != null && href.isNotEmpty) widget.onTapLink!(href);
              },
      ),
    );
  }

  MarkdownStyleSheet _sheet(
    ThemeData theme,
    TextStyle? body,
    TextDirection direction,
  ) {
    final scheme = theme.colorScheme;
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
      a: base.copyWith(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary.withValues(alpha: 0.5),
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

/// Makes an inline `code` span tappable without taking it out of the sentence
/// it sits in.
///
/// The obvious version — return any widget from the builder — is wrong here.
/// The renderer keeps a paragraph's inline children as text widgets and merges
/// them into one rich text at the end; a child it cannot read a span out of is
/// left as a separate item in the `Wrap` that lays the paragraph out. So a
/// `Container` around the code would push the words after it onto their own
/// line. A [Text] carrying a [TextSpan] is read back, merged, and stays in the
/// flow — which is also how the renderer's own links work.
class _NexCodeSpanBuilder extends MarkdownElementBuilder {
  /// Set by the widget on every build; null until it has been.
  void Function(String code)? onTap;

  /// Every recognizer handed to a span, so they can be disposed with the
  /// widget.
  ///
  /// Only on dispose, not per rebuild: a recognizer is still attached to spans
  /// in the tree that produced it, and a re-parse (this renderer re-parses on
  /// a dependency change as well as a rebuild) would otherwise dispose one
  /// still in use. The cost is a handful of small objects per rebuild of a
  /// sheet that rebuilds a handful of times before it closes.
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent;
    // `code` is the tag for both an inline span and the body of a fenced
    // block, and the two want opposite things: a block already scrolls
    // sideways and must keep doing so. A fence keeps the line breaks of its
    // source; an inline span cannot contain one, because the parser folds
    // them into spaces. So the newline is the discriminator.
    final handler = onTap;
    if (handler == null || code.isEmpty || code.contains('\n')) return null;
    final recognizer = TapGestureRecognizer()..onTap = () => handler(code);
    _recognizers.add(recognizer);
    return Text.rich(
      TextSpan(
        text: code,
        style: preferredStyle ?? parentStyle,
        recognizer: recognizer,
      ),
    );
  }
}
