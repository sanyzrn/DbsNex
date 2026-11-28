import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:super_editor/super_editor.dart';

/// Lays a paragraph out by the rule Nex's reading surfaces use.
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
  const _NexParagraphComponentBuilder(this.fallbackDirection);

  /// The interface's direction, used only when no paragraph in the document
  /// carries a strong character of its own.
  final TextDirection fallbackDirection;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    final viewModel = super.createViewModel(document, node);
    if (viewModel is! ParagraphComponentViewModel) return viewModel;
    final direction = _directionOf(document, node);
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

  TextDirection _directionOf(Document document, DocumentNode node) {
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
    return fallbackDirection;
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
class NexParagraphEditor extends StatefulWidget {
  const NexParagraphEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.style,
    this.onChanged,
  });

  /// The plain text being edited, and where the caret is in it.
  ///
  /// Absolute offsets into the whole string — the same contract every
  /// `TextEditingController` in the app already has.
  final TextEditingController controller;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Shows the document but takes no edits. The AI rewrite uses it while it
  /// is working; the text underneath does not change.
  final bool readOnly;

  final TextStyle? style;

  /// Called with the joined text whenever the document changes.
  final ValueChanged<String>? onChanged;

  @override
  State<NexParagraphEditor> createState() => _NexParagraphEditorState();
}

class _NexParagraphEditorState extends State<NexParagraphEditor> {
  late MutableDocument _document;
  late MutableDocumentComposer _composer;
  late Editor _editor;

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

  @override
  void initState() {
    super.initState();
    _build(widget.controller.text, widget.controller.selection);
    widget.controller.addListener(_onControllerChanged);
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
    _tearDown();
    super.dispose();
  }

  void _tearDown() {
    _document.removeListener(_onDocumentChanged);
    _composer.removeListener(_onComposerChanged);
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
    _document.addListener(_onDocumentChanged);
    _composer.addListener(_onComposerChanged);
    _rebuilding = true;
    final start = selection?.start ?? text.length;
    final end = selection?.end ?? text.length;
    _composer.setSelectionWithReason(
      DocumentSelection(
        base: _positionAt(text, start),
        extent: _positionAt(text, end),
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
      if (selection.isValid) {
        _rebuilding = true;
        _composer.setSelectionWithReason(
          DocumentSelection(
            base: _positionAt(text, selection.start),
            extent: _positionAt(text, selection.end),
          ),
          _controllerSelection,
        );
        _rebuilding = false;
      }
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
    _writeController(text);
    widget.onChanged?.call(text);
  }

  void _onComposerChanged() {
    if (_rebuilding) return;
    final selection = _composer.selection;
    if (selection == null) return;
    final text = _knownText;
    final start = _offsetOf(text, selection.base);
    final end = _offsetOf(text, selection.extent);
    if (start == null || end == null) return;
    final current = widget.controller.selection;
    if (current.isValid && current.start == start && current.end == end) return;
    _writeSelection(TextSelection(baseOffset: start, extentOffset: end));
  }

  void _writeController(String text) {
    final selection =
        _absoluteSelection(text) ??
        TextSelection.collapsed(offset: text.length);
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

  TextSelection? _absoluteSelection(String text) {
    final selection = _composer.selection;
    if (selection == null) return null;
    final start = _offsetOf(text, selection.base);
    final end = _offsetOf(text, selection.extent);
    if (start == null || end == null) return null;
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  static String _join(Document document) => document
      .map((node) => node is TextNode ? node.text.toPlainText() : '')
      .join('\n');

  /// Where [text]'s [offset] sits in a fresh document: the paragraph it is in,
  /// and how far into that paragraph.
  ///
  /// Each paragraph costs its own length plus the newline that joins it to the
  /// next, which is exactly how [_build] split the text.
  DocumentPosition _positionAt(String text, int offset) {
    final target = offset.clamp(0, text.length);
    var remaining = target;
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
  int? _offsetOf(String text, DocumentPosition position) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = widget.style ?? theme.textTheme.bodyLarge;
    final style = body?.copyWith(
      color: theme.colorScheme.onSurface,
      // The engine draws each paragraph flush to its own side rather than
      // centring it, so the leading has to come from the style, not from a
      // padding that would shift one side only.
      height: body.height ?? 1.5,
    );
    final editor = SuperEditor(
      editor: _editor,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      // The note is prose, and a note keeps its own formatting as Markdown in
      // its text. Turning markdown into blocks here would change what the note
      // is, so the editor shows the same plain source the field showed, with
      // only the paragraph component.
      componentBuilders: [
        _NexParagraphComponentBuilder(Directionality.of(context)),
      ],
      stylesheet: defaultStylesheet.copyWith(
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
      ),
      selectionStyle: SelectionStyles(
        selectionColor: theme.colorScheme.primary.withValues(alpha: 0.22),
      ),
    );
    // While the AI rewrite runs the document is shown, not taken: the text is
    // the model's to replace, and an edit under it would be applied to a value
    // that is about to be thrown away.
    return widget.readOnly ? IgnorePointer(child: editor) : editor;
  }
}
