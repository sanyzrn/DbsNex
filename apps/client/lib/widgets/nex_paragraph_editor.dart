import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:super_editor/super_editor.dart';

import '../l10n/app_localizations.dart';
import 'text_format_menu.dart';

/// Resolves every paragraph's direction once, from the paragraphs' own text,
/// and hands it to each paragraph component as it is laid out.
///
/// The map is rebuilt whenever the text changes; a node the map has not seen
/// yet (the second half of a split) falls back to the same neighbour walk for
/// that one node, so a relayout that runs before the map is refreshed is still
/// right — just not cached.
///
/// Super Editor's own paragraph builder decides direction from the paragraph's
/// **first character**: anything outside a right-to-left block answers left to
/// right. That is wrong in both directions for real notes — a paragraph that
/// opens with a product name («Nex را باز کن») would be laid out left to right,
/// and a paragraph of Persian digits («۱۲۳») would be laid out right to left
/// although digits carry no direction at all (UAX #9, classes EN and AN, which
/// P2 skips).
///
/// Nex's rule is the one the rest of the app reads by: the paragraph's own first
/// **strong** character, and when it has none — empty, digits, punctuation — the
/// nearest paragraph before it that does, then the nearest after, then the
/// surface's own direction. It is the rule the field's caret used to follow for
/// only one paragraph at a time; here every paragraph follows it at once, and
/// none of them depends on the caret.
class _NexParagraphComponentBuilder extends ParagraphComponentBuilder {
  const _NexParagraphComponentBuilder(this.resolver);

  final _NexDirectionResolver resolver;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    final viewModel = super.createViewModel(document, node);
    if (viewModel is! ParagraphComponentViewModel) return viewModel;
    final direction = resolver.directionOf(document, node);
    viewModel.textDirection = direction;
    // Alignment is the paragraph's own side, not the document's: a per-
    // paragraph direction with one shared alignment would put a Persian
    // paragraph on the left of an English note, which is the bug this file
    // exists to remove.
    viewModel.textAlignment = direction == TextDirection.rtl
        ? TextAlign.right
        : TextAlign.left;
    return viewModel;
  }
}

/// The per-document direction cache behind [_NexParagraphComponentBuilder].
///
/// One instance lives as long as the state, so a relayout caused by a
/// selection or a drag reads the map instead of walking the document again.
/// It is rebuilt only when the text changes — once per edit, not once per
/// paragraph and certainly not once per frame.
class _NexDirectionResolver {
  Map<String, TextDirection> directions = const {};

  /// The interface's direction, used only when no paragraph in the document
  /// carries a strong character of its own.
  TextDirection fallback = TextDirection.ltr;

  TextDirection directionOf(Document document, DocumentNode node) =>
      directions[node.id] ?? _walk(document, node);

  TextDirection _walk(Document document, DocumentNode node) {
    final own = _strongDirection(node);
    if (own != null) return own;
    var before = document.getNodeBeforeById(node.id);
    while (before != null) {
      final direction = _strongDirection(before);
      if (direction != null) return direction;
      before = document.getNodeBeforeById(before.id);
    }
    var after = document.getNodeAfterById(node.id);
    while (after != null) {
      final direction = _strongDirection(after);
      if (direction != null) return direction;
      after = document.getNodeAfterById(after.id);
    }
    return fallback;
  }

  static TextDirection? _strongDirection(DocumentNode node) =>
      node is TextNode ? nexDirectionOf(node.text.toPlainText()) : null;
}

/// The app's prose editor: one editable document whose every paragraph is laid
/// out in its own direction, against its own side, at the same time.
///
/// ## Why this is not a `TextField`
///
/// Flutter's text engine builds one `ui.Paragraph` for a whole field, and a
/// paragraph has exactly one base direction. So a field can be right-to-left
/// *or* left-to-right, never both: an English line inside a Persian note has
/// its full stop resolved against the Persian base and lands on the wrong end,
/// and every line is aligned to the same side. Two earlier answers were tried
/// and each failed for its own reason:
///
/// * Android's own `EditText` (ADR-037, 1.91–2.9.3) gave every paragraph its
///   own direction natively, and its keyboard handoffs between the embedded
///   view and Flutter's fields closed and reopened the keyboard on the owner's
///   devices. The engine's input-client switch is below anything Dart can fix,
///   so 2.9.4 removed the native editor.
/// * 2.9.4's replacement was one Flutter field laid out around the paragraph
///   the caret is in. It kept the keyboard, and it made the *active* paragraph
///   right — but at the cost of turning the whole document with the caret:
///   paragraphs in the other direction sat on the caret paragraph's side,
///   crossed to the other side as the caret moved, and the selection handles
///   travelled with that relayout. That is the report this file answers.
///
/// The model that works is the one every document editor uses: **one text
/// component per paragraph**, each laid out by the framework with its own
/// base direction, over **one IME connection for the whole document**. This
/// widget is that model, from Super Editor's document engine (MIT), wired to
/// the plain string Nex already stores.
///
/// ## What Super Editor brings, and what it is trusted for
///
/// A `ParagraphComponent` resolves its direction from its own text
/// (`getParagraphDirection`, the same first-strong rule as [nexDirectionOf])
/// and aligns to that direction's start. That is per-paragraph direction and
/// alignment, simultaneously, with no caret involvement at all: moving the
/// caret or dragging a selection cannot change any paragraph's layout, because
/// no paragraph's layout depends on the selection.
///
/// The document-level input client is the other half. A `deleteSurroundingText`
/// at the start of one paragraph reaches the document, not a field that has
/// nothing before its offset zero, so Backspace joins paragraphs instead of
/// being swallowed; Enter splits them; a selection that spans paragraphs is one
/// selection in one model, with the handles, magnifier and toolbar drawn from
/// the components it covers. Undo, redo, copy, cut, paste and the platform
/// keyboard shortcuts are the engine's.
///
/// ## The data is still a plain string
///
/// Nex stores a note as plain text, and this keeps that promise. The document
/// is built from the string — one paragraph per line, empty lines included —
/// and written back by joining the paragraphs with `\n`. Nothing is written
/// into the stored text to make the layout work: no marks, no isolates, no
/// escape characters. A note saved by this editor is byte-identical to one
/// saved by the field it replaced, so old notes open unchanged and new notes
/// open in every older version of the app.
///
/// The [controller] remains the source of truth in both directions. Typing
/// writes the joined text into it the frame it happens; an AI rewrite, a draft
/// recovery or the editor's own undo writing into it rebuilds the document.
///
/// ## The cost of a keystroke
///
/// A note is a string, and a string is what the controller and every reader of
/// it expect, so a keystroke does have to produce the whole note once. That is
/// what this state does and all it does: join the paragraphs, write the
/// controller, refresh the direction map. An earlier version also kept a
/// paragraph cache and a binary-search offset table; measured against this
/// shape on 500, 2000 and 5000-line notes it bought nothing — the cost is the
/// join, the IME serialisation upstream and the layout — so it was removed
/// rather than maintained. See
/// `docs/development/nex-2.9.5-per-paragraph-editing.md`.
///
/// ## Read-only means no input, not a blocked finger
///
/// [readOnly] is not `IgnorePointer`. A widget under an ignored pointer still
/// holds the platform input connection, so a hardware keyboard or an IME can
/// keep editing a document that is only being shown — which during an AI
/// rewrite would edit the text that is about to be replaced. Read-only renders
/// the same document through `SuperReader`, which has no input connection at
/// all, so nothing can arrive.
///
/// ## A drop-in field
///
/// Two things a `TextField` gives for free are given here too, so a field can
/// move to this engine without losing anything: [decoration] (hint included)
/// around the text, and the line box [minLines]/[maxLines] describe — growing
/// with the text up to the maximum, then scrolling. [formatting] adds the same
/// seven commands the capture sheet's selection menu offers, in a small bar
/// above the selection, because Super Editor draws its own selection UI and
/// the platform's context menu is not part of it.
class NexParagraphEditor extends StatefulWidget {
  const NexParagraphEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.enabled = true,
    this.style,
    this.decoration = const InputDecoration(),
    this.minLines,
    this.maxLines,
    this.formatting = false,
    this.onChanged,
  });

  /// The plain text being edited, and where the caret is in it.
  ///
  /// Absolute offsets into the whole string — the same contract every
  /// `TextEditingController` in the app already has.
  final TextEditingController controller;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Shows the document but takes no input: no IME connection, no caret.
  ///
  /// The AI rewrite uses it while it is working; the text underneath does not
  /// change, and a key pressed during it cannot change it either.
  final bool readOnly;

  /// False dims the field and takes no input, as a disabled `TextField` does.
  final bool enabled;

  final TextStyle? style;

  /// The field's frame: hint, helper, error, borders and padding.
  ///
  /// The engine draws the text; this draws what a `TextField` would draw
  /// around it, through the same `InputDecorator`, so the theme's borders,
  /// hints and colours arrive unchanged.
  final InputDecoration decoration;

  /// The line box: at least [minLines] tall, and with [maxLines] set, no
  /// taller — the text scrolls inside after that.
  final int? minLines;
  final int? maxLines;

  /// Bold, italic, monospace, strikethrough, quote, link and clear, in a bar
  /// over the selection — see [NexTextFormatting].
  final bool formatting;

  /// Called with the joined text whenever the document changes.
  final ValueChanged<String>? onChanged;

  @override
  State<NexParagraphEditor> createState() => _NexParagraphEditorState();
}

class _NexParagraphEditorState extends State<NexParagraphEditor> {
  late MutableDocument _document;
  late MutableDocumentComposer _composer;
  late Editor _editor;

  final _resolver = _NexDirectionResolver();

  /// The document's scroll position, kept so the format bar can be placed in
  /// the viewport rather than in the document.
  final _scroll = ScrollController();

  /// The laid-out document, for the format bar's anchor. Super Editor exposes
  /// it through the key its viewport was built with.
  final _layoutKey = GlobalKey();

  /// Why a selection changed when the caller set it rather than a finger.
  ///
  /// The engine treats a user interaction differently from a programmatic
  /// selection — it puts the selection toolbar and the drag handles up for the
  /// one, and leaves them down for the other, exactly as a `TextField` does.
  /// An AI rewrite, a recovered draft and the sheet restoring its caret are
  /// the other.
  static const Object _controllerSelection = 'nexControllerSelection';

  /// The text the document currently stands for. Compared against the
  /// controller's text to tell an external write from the echo of our own.
  String _knownText = '';

  /// How many documents this state has built. Node ids only have to be unique
  /// within one document, but a generation keeps them from repeating in
  /// diagnostics and in any listener that outlives a rebuild.
  int _generation = 0;

  /// True while this widget is writing the controller, so the controller's
  /// own notification is not mistaken for an external edit.
  bool _writingController = false;

  /// True while the document is being rebuilt from an external write, so the
  /// composer's clears and restores are not written back over the caret the
  /// caller asked for.
  bool _rebuilding = false;

  /// Set by a format command: the bar goes away until the selection moves
  /// again, the way a platform's menu closes after a command.
  bool _formatBarDismissed = false;

  @override
  void initState() {
    super.initState();
    _build(widget.controller.text, widget.controller.selection);
    widget.controller.addListener(_onControllerChanged);
    _scroll.addListener(_onScrolled);
  }

  @override
  void didUpdateWidget(NexParagraphEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _build(widget.controller.text, widget.controller.selection);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scroll
      ..removeListener(_onScrolled)
      ..dispose();
    _tearDown();
    super.dispose();
  }

  void _onScrolled() {
    if (widget.formatting) setState(() {});
  }

  void _tearDown() {
    _document.removeListener(_onDocumentChanged);
    _composer.selectionNotifier.removeListener(_onComposerChanged);
    _document.dispose();
    _editor.dispose();
  }

  /// Builds a fresh document and editor for [text], with the caret at
  /// [selection] (or at the end when it does not point anywhere).
  void _build(String text, TextSelection? selection) {
    final generation = ++_generation;
    final lines = text.split('\n');
    _document = MutableDocument(
      nodes: [
        for (var i = 0; i < lines.length; i++)
          ParagraphNode(
            id: 'nex-$generation-$i',
            text: AttributedText(lines[i]),
          ),
      ],
    );
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _composer,
      isHistoryEnabled: true,
    );
    _knownText = text;
    _resolver.directions = const {};
    _document.addListener(_onDocumentChanged);
    // The composer's own listeners hear about composing regions and
    // interaction mode; the selection is published on its notifier. Listening
    // to the composer alone would leave the controller's caret where it was
    // while a finger moved the editor's — and the formatting bar reads that
    // caret.
    _composer.selectionNotifier.addListener(_onComposerChanged);
    final caret = selection != null && selection.isValid
        ? selection
        : TextSelection.collapsed(offset: text.length);
    _applySelection(caret);
  }

  /// Adopts [selection] as the document's selection without treating it as a
  /// user interaction.
  void _applySelection(TextSelection selection) {
    _rebuilding = true;
    _composer.setSelectionWithReason(
      DocumentSelection(
        base: _positionAt(selection.baseOffset),
        extent: _positionAt(selection.extentOffset),
      ),
      _controllerSelection,
    );
    _rebuilding = false;
  }

  /// Rebuilds the document after an external write — an AI rewrite, a
  /// recovered draft, the sheet's undo. The engine's keyboard state is
  /// replaced with it; the controller already holds the truth.
  void _rebuildFromController() {
    final text = widget.controller.text;
    if (text == _knownText) {
      // Selection-only change: follow it in the document instead of
      // rebuilding, which would drop the composition and the scroll position.
      final selection = widget.controller.selection;
      if (selection.isValid) _applySelection(selection);
      return;
    }
    setState(() {
      _tearDown();
      _build(text, widget.controller.selection);
    });
    if (widget.autofocus) widget.focusNode?.requestFocus();
  }

  void _onControllerChanged() {
    if (_writingController) return;
    _rebuildFromController();
  }

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    final text = _join(_document);
    if (text == _knownText) return;
    _knownText = text;
    _resolver.directions = _resolveDirections();
    _formatBarDismissed = false;
    _writeController(text);
    widget.onChanged?.call(text);
    if (widget.minLines != null) setState(() {});
  }

  /// One pass over the paragraphs: each direction is its own, else the nearest
  /// before, else the nearest after, else the surface's.
  ///
  /// Computed once per text change and read by every paragraph while it lays
  /// out, so a selection drag — which relayouts the components — does not walk
  /// the document again.
  Map<String, TextDirection> _resolveDirections() {
    final ids = <String>[];
    final own = <TextDirection?>[];
    for (final node in _document) {
      ids.add(node.id);
      own.add(
        node is TextNode ? nexDirectionOf(node.text.toPlainText()) : null,
      );
    }
    final count = ids.length;
    final before = List<TextDirection?>.filled(count, null);
    TextDirection? carry;
    for (var i = 0; i < count; i++) {
      before[i] = carry;
      carry = own[i] ?? carry;
    }
    final after = List<TextDirection?>.filled(count, null);
    carry = null;
    for (var i = count - 1; i >= 0; i--) {
      after[i] = carry;
      carry = own[i] ?? carry;
    }
    final fallback = _resolver.fallback;
    return {
      for (var i = 0; i < count; i++)
        ids[i]: own[i] ?? before[i] ?? after[i] ?? fallback,
    };
  }

  void _onComposerChanged() {
    if (_rebuilding) return;
    final selection = _composer.selection;
    if (selection == null) return;
    _formatBarDismissed = false;
    final start = _offsetOf(selection.base);
    final end = _offsetOf(selection.extent);
    if (start == null || end == null) return;
    final current = widget.controller.selection;
    // Compared field by field, not start/end: an anchor dragged upwards has
    // base > extent, and normalising it here would turn the selection around
    // and send the next Shift+arrow to the wrong end.
    if (current.isValid &&
        current.baseOffset == start &&
        current.extentOffset == end) {
      return;
    }
    _writeSelection(TextSelection(baseOffset: start, extentOffset: end));
  }

  void _writeController(String text) {
    final selection =
        _absoluteSelection() ?? TextSelection.collapsed(offset: text.length);
    _writingController = true;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: selection,
    );
    _writingController = false;
  }

  void _writeSelection(TextSelection selection) {
    _writingController = true;
    widget.controller.value = widget.controller.value.copyWith(
      selection: selection,
      composing: TextRange.empty,
    );
    _writingController = false;
  }

  TextSelection? _absoluteSelection() {
    final selection = _composer.selection;
    if (selection == null) return null;
    final start = _offsetOf(selection.base);
    final end = _offsetOf(selection.extent);
    if (start == null || end == null) return null;
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  static String _join(Document document) => document
      .map((node) => node is TextNode ? node.text.toPlainText() : '')
      .join('\n');

  /// Where [offset] sits in the document: the paragraph it is in, and how far
  /// into that paragraph.
  DocumentPosition _positionAt(int offset) {
    var remaining = offset.clamp(0, _knownText.length);
    for (final node in _document) {
      final length = node is TextNode ? node.text.length : 0;
      if (remaining <= length) {
        return DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: remaining),
        );
      }
      remaining -= length + 1;
    }
    final last = _document.lastOrNull;
    return DocumentPosition(
      nodeId: last?.id ?? '',
      nodePosition: TextNodePosition(
        offset: last is TextNode ? last.text.length : 0,
      ),
    );
  }

  /// The reverse of [_positionAt]: an absolute offset into the joined text.
  int? _offsetOf(DocumentPosition position) {
    var offset = 0;
    for (final node in _document) {
      if (node.id == position.nodeId) {
        final length = node is TextNode ? node.text.length : 0;
        final inParagraph = position.nodePosition is TextNodePosition
            ? (position.nodePosition as TextNodePosition).offset
            : 0;
        return offset + inParagraph.clamp(0, length);
      }
      offset += (node is TextNode ? node.text.length : 0) + 1;
    }
    return null;
  }

  /// Applies a formatting command to the controller's selection and writes the
  /// result back, which is the same door the AI rewrite comes through: the
  /// document is rebuilt from the new string, so the note keeps being one
  /// plain string with Markdown in it.
  Future<void> _format(_NexFormatCommand command) async {
    final value = widget.controller.value;
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final start = selection.start;
    final end = selection.end;
    NexFormattedText? result;
    switch (command) {
      case _NexFormatCommand.bold:
        result = NexTextFormatting.toggleInline(
          value.text,
          start,
          end,
          NexInlineFormat.bold,
        );
      case _NexFormatCommand.italic:
        result = NexTextFormatting.toggleInline(
          value.text,
          start,
          end,
          NexInlineFormat.italic,
        );
      case _NexFormatCommand.mono:
        result = NexTextFormatting.toggleInline(
          value.text,
          start,
          end,
          NexInlineFormat.mono,
        );
      case _NexFormatCommand.strikethrough:
        result = NexTextFormatting.toggleInline(
          value.text,
          start,
          end,
          NexInlineFormat.strikethrough,
        );
      case _NexFormatCommand.quote:
        result = NexTextFormatting.toggleQuote(value.text, start, end);
      case _NexFormatCommand.link:
        final url = await nexAskForLinkUrl(context);
        if (!mounted || url == null || url.isEmpty) return;
        result = NexTextFormatting.link(value.text, start, end, url);
      case _NexFormatCommand.clear:
        result = NexTextFormatting.clear(value.text, start, end);
    }
    if (!mounted) return;
    setState(() => _formatBarDismissed = true);
    widget.controller.value = TextEditingValue(
      text: result.text,
      selection: TextSelection(
        baseOffset: result.start,
        extentOffset: result.end,
      ),
    );
  }

  /// The line height the style draws with, text scale included.
  double _lineHeight(BuildContext context) {
    final style =
        widget.style ??
        DefaultTextStyle.of(context).style
            .copyWith(color: Theme.of(context).colorScheme.onSurface);
    final fontSize = style.fontSize ?? 16;
    final factor = style.height ?? 1.5;
    return MediaQuery.textScalerOf(context).scale(fontSize) * factor;
  }

  /// The height the field wants: its text's lines, inside the box its
  /// [NexParagraphEditor.minLines]/[NexParagraphEditor.maxLines] describe.
  double _fieldHeight(BuildContext context) {
    final lines = '\n'.allMatches(widget.controller.text).length + 1;
    final minLines = widget.minLines ?? 1;
    final maxLines = widget.maxLines;
    final visible = maxLines == null
        ? math.max(lines, minLines)
        : lines.clamp(minLines, maxLines);
    return visible * _lineHeight(context);
  }

  /// Where the format bar goes: just above the selection, in viewport
  /// coordinates, and never off the top.
  Rect? _selectionRect() {
    final selection = _composer.selection;
    if (selection == null || selection.isCollapsed) return null;
    final state = _layoutKey.currentState;
    if (state == null) return null;
    final layout = state as DocumentLayout;
    final rect = layout.getRectForSelection(selection.base, selection.extent);
    if (rect == null) return null;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    return rect.shift(Offset(0, -offset));
  }

  Widget _formatBar(BuildContext context, Rect anchor) {
    final l10n = AppLocalizations.of(context);
    final entries = <(_NexFormatCommand, String)>[
      (_NexFormatCommand.bold, l10n.formatBold),
      (_NexFormatCommand.italic, l10n.formatItalic),
      (_NexFormatCommand.mono, l10n.formatMono),
      (_NexFormatCommand.strikethrough, l10n.formatStrikethrough),
      (_NexFormatCommand.quote, l10n.formatQuote),
      (_NexFormatCommand.link, l10n.formatLink),
      (_NexFormatCommand.clear, l10n.formatClear),
    ];
    return Positioned(
      left: 0,
      right: 0,
      top: math.max(0, anchor.top - 44),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(NexRadius.sm),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (command, label) in entries)
                  TextButton(
                    onPressed: () => _format(command),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: NexSpacing.xs,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(label, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = widget.style ?? theme.textTheme.bodyLarge;
    final style = body?.copyWith(
      color: widget.enabled ? theme.colorScheme.onSurface : theme.disabledColor,
      // The engine draws each paragraph flush to its own side rather than
      // centring it, so the leading has to come from the style, not from a
      // padding that would shift one side only.
      height: body.height ?? 1.5,
    );
    final direction = Directionality.of(context);
    if (_resolver.fallback != direction || _resolver.directions.isEmpty) {
      _resolver.fallback = direction;
      _resolver.directions = _resolveDirections();
    }
    final stylesheet = defaultStylesheet.copyWith(
      addRulesAfter: [
        StyleRule(BlockSelector.all, (document, node) {
          final rules = <String, Object>{
            Styles.padding: const CascadingPadding.symmetric(
              horizontal: 0,
              vertical: 0,
            ),
          };
          final textStyle = style;
          if (textStyle != null) rules[Styles.textStyle] = textStyle;
          return rules;
        }),
      ],
    );
    final builders = [_NexParagraphComponentBuilder(_resolver)];
    final selectionStyle = SelectionStyles(
      selectionColor: theme.colorScheme.primary.withValues(alpha: 0.22),
    );
    final Widget content;
    if (widget.readOnly || !widget.enabled) {
      // No IME connection at all: a key pressed while the document is only
      // being shown has nowhere to arrive, so it cannot edit the text that is
      // about to be replaced.
      content = SuperReader(
        editor: _editor,
        stylesheet: stylesheet,
        componentBuilders: builders,
        selectionStyle: selectionStyle,
      );
    } else {
      content = SuperEditor(
        editor: _editor,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        scrollController: _scroll,
        documentLayoutKey: _layoutKey,
        // The field decides its own height from its lines and may sit inside a
        // sheet that already scrolls; the editor then shrinks to that height
        // instead of demanding a viewport of its own.
        shrinkWrap: true,
        // The note is prose, and a note keeps its own formatting as Markdown in
        // its text. Turning markdown into blocks here would change what the
        // note is, so the editor shows the same plain source the field showed,
        // with only the paragraph component.
        componentBuilders: builders,
        stylesheet: stylesheet,
        selectionStyle: selectionStyle,
      );
    }
    final showFormatBar =
        widget.formatting &&
        !widget.readOnly &&
        widget.enabled &&
        !_formatBarDismissed &&
        (_composer.selection?.isCollapsed ?? true) == false;
    final anchor = showFormatBar ? _selectionRect() : null;
    // A caller that says nothing about lines wants the whole space it is
    // given — the note sheet gives the editor an `Expanded` and lets it fill
    // the page and scroll. Only a caller that describes a field gets a field:
    // the box its lines ask for, and the frame around it.
    if (widget.minLines == null && widget.maxLines == null) return content;
    // No `LayoutBuilder` here: the engine mounts slotted render objects
    // (its viewport and its selection overlay), and a subtree mounted during
    // someone else's layout pass attaches those slots to the wrong parent.
    // The height comes from the text, and a parent that is shorter simply
    // clips it and lets the engine scroll.
    final desired = _fieldHeight(context);
    final box = math.max(desired, _lineHeight(context));
    final fieldBody = SizedBox(
      height: box,
      child: anchor == null
          ? content
          : ClipRect(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: content),
                  _formatBar(context, anchor),
                ],
              ),
            ),
    );
    return _NexFieldFrame(
      decoration: widget.decoration,
      isEmpty: widget.controller.text.isEmpty,
      isEnabled: widget.enabled,
      child: fieldBody,
    );
  }
}

/// The frame a [InputDecoration] draws around a field, without the
/// [InputDecorator] that would break the engine.
///
/// Super Editor's viewport and its selection overlay are *slotted* render
/// objects, and `InputDecorator` is one too: a slotted child nested inside a
/// slotted parent lands in the wrong slot and the layout throws. The frame that
/// matters — the hint, the fill, the outline and the padding — is small enough
/// to draw here, and fields that need a label, an error line, a counter or an
/// icon keep the platform field instead (see [NexTextField]).
class _NexFieldFrame extends StatelessWidget {
  const _NexFieldFrame({
    required this.decoration,
    required this.isEmpty,
    required this.isEnabled,
    required this.child,
  });

  final InputDecoration decoration;
  final bool isEmpty;
  final bool isEnabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final side = decoration.enabledBorder is OutlineInputBorder
        ? (decoration.enabledBorder! as OutlineInputBorder).borderSide
        : (decoration.border is OutlineInputBorder
              ? (decoration.border! as OutlineInputBorder).borderSide
              : BorderSide.none);
    final radius = decoration.border is OutlineInputBorder
        ? (decoration.border! as OutlineInputBorder).borderRadius
        : const BorderRadius.all(Radius.circular(NexRadius.sm));
    final fill = decoration.fillColor;
    final padding =
        decoration.contentPadding ??
        const EdgeInsets.symmetric(
          horizontal: NexSpacing.xs,
          vertical: NexSpacing.xs,
        );
    final text = decoration.hintText;
    final hintStyle =
        decoration.hintStyle ??
        theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: decoration.filled == true ? fill : null,
        borderRadius: radius,
        border: side == BorderSide.none
            ? null
            : Border.all(
                color: isEnabled ? side.color : theme.disabledColor,
                width: side.width,
              ),
      ),
      child: Padding(
        padding: padding,
        child: text == null || !isEmpty
            ? child
            : Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Text(
                          text,
                          style: hintStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                        ),
                      ),
                    ),
                  ),
                  child,
                ],
              ),
      ),
    );
  }
}

enum _NexFormatCommand { bold, italic, mono, strikethrough, quote, link, clear }
