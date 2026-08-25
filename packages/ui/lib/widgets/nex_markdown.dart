import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

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
class NexMarkdown extends StatelessWidget {
  const NexMarkdown(
    this.text, {
    super.key,
    this.style,
    this.onTapLink,
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

  /// Whether the rendered text can be selected.
  ///
  /// True for a document someone opened to read, where lifting a line out of
  /// it is the point. False in the assistant's thread, where selection inside
  /// a scrolling list fights the scroll gesture and hands the user a partial
  /// paste — that surface copies a whole message on long-press instead, and a
  /// selectable child would swallow the long-press before it arrives.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final direction = nexDirectionOf(text) ?? Directionality.of(context);
    return Directionality(
      textDirection: direction,
      child: MarkdownBody(
        data: text,
        selectable: selectable,
        fitContent: false,
        styleSheet: _sheet(
          theme,
          style ?? theme.textTheme.bodyLarge,
          direction,
        ),
        onTapLink: onTapLink == null
            ? null
            : (_, href, _) {
                if (href != null && href.isNotEmpty) onTapLink!(href);
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

/// Whether [text] is worth handing to [NexMarkdown] rather than showing plain.
///
/// Used for the assistant's replies, which are Markdown only when the model
/// chose to write Markdown. Rendering an ordinary sentence through a Markdown
/// parser is not wrong so much as pointless, and it has one real cost: a lone
/// `*` or `_` in prose — or in Persian, a line that opens with `-` as a dash —
/// would be eaten as markup. So the renderer is used only where there is a
/// structure to gain by it.
///
/// Deliberately conservative. It looks for constructs that are unambiguous at
/// the start of a line (a heading, a fence, a list marker, a quote, a rule, a
/// table row) or paired inline (`**bold**`, `` `code` ``), and ignores
/// everything else.
bool nexLooksLikeMarkdown(String text) {
  if (text.trim().isEmpty) return false;
  if (text.contains('```')) return true;
  if (RegExp(r'(^|\n)\s{0,3}#{1,6}\s+\S').hasMatch(text)) return true;
  if (RegExp(r'(^|\n)\s{0,3}([-*+]|\d{1,9}[.)])\s+\S').hasMatch(text)) {
    return true;
  }
  if (RegExp(r'(^|\n)\s{0,3}>\s+\S').hasMatch(text)) return true;
  if (RegExp(r'(^|\n)\s{0,3}(([-*_])\s*){3,}\s*(\n|$)').hasMatch(text)) {
    return true;
  }
  if (RegExp(r'(^|\n)\s*\|.+\|\s*(\n|$)').hasMatch(text)) return true;
  if (RegExp(r'\*\*[^*\n]+\*\*').hasMatch(text)) return true;
  if (RegExp(r'`[^`\n]+`').hasMatch(text)) return true;
  if (RegExp(r'\[[^\]\n]+\]\([^)\s]+\)').hasMatch(text)) return true;
  return false;
}
