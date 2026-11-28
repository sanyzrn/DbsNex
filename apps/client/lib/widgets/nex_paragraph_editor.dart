import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:super_editor/super_editor.dart';

import '../l10n/app_localizations.dart';
import 'nex_caret_movement.dart';
import 'nex_field_chrome.dart';
import 'text_format_menu.dart';

part 'nex_paragraph_editor_view.dart';

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

/// Edits a plain string as one document with an independent bidi layout for
/// every paragraph. The document has one IME connection and stores line
/// breaks as newlines in [controller].
///
/// Fields use [InputDecorator] and grow to their wrapped text within their
/// line and parent constraints. The note sheet uses a fill-height viewport.
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
    this.asField = false,
    this.expands = false,
    this.minLines,
    this.maxLines,
    this.formatting = false,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType = TextInputType.multiline,
    this.textInputAction = TextInputAction.newline,
    this.textCapitalization = TextCapitalization.sentences,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enableIMEPersonalizedLearning = true,
    this.maxLength,
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
  final bool asField;
  final bool expands;
  final int? minLines;
  final int? maxLines;

  /// Bold, italic, monospace, strikethrough, quote, link and clear, in a bar
  /// over the selection — see [NexTextFormatting].
  final bool formatting;

  /// Called with the joined text whenever the document changes.
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool enableIMEPersonalizedLearning;
  final int? maxLength;

  @override
  State<NexParagraphEditor> createState() => _NexParagraphEditorState();
}

class _NexParagraphEditorState extends State<NexParagraphEditor> {
  late MutableDocument _document;
  late MutableDocumentComposer _composer;
  late Editor _editor;

  static int _nextInputId = 0;
  final _inputRole = 'nex-prose-${_nextInputId++}';
  final _resolver = _NexDirectionResolver();
  late final _builders = [_NexParagraphComponentBuilder(_resolver)];
  late final _ime = _NexImeActions(_submit);
  final _localFocus = FocusNode(debugLabel: 'Nex prose editor');
  FocusNode get _focus => widget.focusNode ?? _localFocus;

  TextStyle? _lastStyle;
  Stylesheet? _stylesheet;

  bool get _isField =>
      widget.asField || widget.minLines != null || widget.maxLines != null;

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
  static const String _controllerSelection = 'nexControllerSelection';

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
      _tearDown(replacing: true);
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
    _localFocus.dispose();
    super.dispose();
  }

  void _onScrolled() {
    if (widget.formatting) setState(() {});
  }

  void _tearDown({bool replacing = false}) {
    final document = _document;
    final composer = _composer;
    final editor = _editor;
    document.removeListener(_onDocumentChanged);
    composer.selectionNotifier.removeListener(_onComposerChanged);
    composer.composingRegion.removeListener(_onCompositionChanged);
    void disposeEditor() {
      editor.dispose();
      document.dispose();
      composer.dispose();
    }

    if (replacing) {
      // The previous view and IME detach their listeners during this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => disposeEditor());
    } else {
      disposeEditor();
    }
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
    // All paragraphs remain plain source, including Markdown, URLs and dashes.
    _editor.reactionPipeline
      ..clear()
      ..add(FunctionalEditReaction(modifyContent: _normalizeEdit));
    _knownText = text;
    _resolver.directions = const {};
    _document.addListener(_onDocumentChanged);
    // The composer's own listeners hear about composing regions and
    // interaction mode; the selection is published on its notifier. Listening
    // to the composer alone would leave the controller's caret where it was
    // while a finger moved the editor's — and the formatting bar reads that
    // caret.
    _composer.selectionNotifier.addListener(_onComposerChanged);
    _composer.composingRegion.addListener(_onCompositionChanged);
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
        extent: _positionAt(
          selection.extentOffset,
          affinity: selection.affinity,
        ),
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
        _applySelection(selection);
        if (widget.formatting) setState(() {});
      }
      return;
    }
    setState(() {
      _tearDown(replacing: true);
      _build(text, widget.controller.selection);
    });
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
    if (_isField) setState(() {});
  }

  /// One pass over the paragraphs: each direction is its own, else the nearest
  /// before, else the nearest after, else the surface's.
  ///
  /// Computed once per text change and read by every paragraph while it lays
  /// out, so a selection drag — which relayouts the components — does not walk
  /// the document again.
  Map<String, TextDirection> _resolveDirections() {
    final result = <String, TextDirection>{};
    final leadingNeutralNodes = <String>[];
    TextDirection? previous;
    TextDirection? first;
    for (final node in _document) {
      previous = _NexDirectionResolver._strongDirection(node) ?? previous;
      final direction = previous;
      if (direction == null) {
        leadingNeutralNodes.add(node.id);
      } else {
        first ??= direction;
        result[node.id] = direction;
      }
    }
    final leadingDirection = first ?? _resolver.fallback;
    for (final id in leadingNeutralNodes) {
      result[id] = leadingDirection;
    }
    return result;
  }

  void _onComposerChanged() {
    if (_rebuilding) return;
    _formatBarDismissed = false;
    if (widget.formatting) setState(() {});
    final selection = _absoluteSelection();
    if (selection == null ||
        selection.end > widget.controller.text.length ||
        selection == widget.controller.selection) {
      return;
    }
    _syncController(widget.controller.value.copyWith(selection: selection));
  }

  void _onCompositionChanged() {
    if (_rebuilding) return;
    final current = widget.controller.value;
    final composing = _absoluteComposing();
    if (composing != current.composing &&
        composing.end <= current.text.length) {
      _syncController(current.copyWith(composing: composing));
    }
  }

  void _writeController(String text) {
    final selection =
        _absoluteSelection() ?? TextSelection.collapsed(offset: text.length);
    final composing = _absoluteComposing();
    _syncController(
      TextEditingValue(
        text: text,
        selection: selection,
        composing: composing.end <= text.length ? composing : TextRange.empty,
      ),
    );
  }

  void _syncController(TextEditingValue value) {
    _writingController = true;
    try {
      widget.controller.value = value;
    } finally {
      _writingController = false;
    }
  }

  TextRange _absoluteComposing() {
    final range = _composer.composingRegion.value;
    if (range == null) return TextRange.empty;
    final start = _offsetOf(range.start);
    final end = _offsetOf(range.end);
    return start == null || end == null
        ? TextRange.empty
        : TextRange(start: math.min(start, end), end: math.max(start, end));
  }

  TextSelection? _absoluteSelection() {
    final selection = _composer.selection;
    if (selection == null) return null;
    final start = _offsetOf(selection.base);
    final end = _offsetOf(selection.extent);
    if (start == null || end == null) return null;
    final extent = selection.extent.nodePosition;
    return TextSelection(
      baseOffset: start,
      extentOffset: end,
      affinity: extent is TextNodePosition
          ? extent.affinity
          : TextAffinity.downstream,
    );
  }

  static String _join(Document document) => document
      .map((node) => node is TextNode ? node.text.toPlainText() : '')
      .join('\n');

  /// Where [offset] sits in the document: the paragraph it is in, and how far
  /// into that paragraph.
  DocumentPosition _positionAt(
    int offset, {
    TextAffinity affinity = TextAffinity.downstream,
  }) {
    var remaining = math.max(0, offset);
    for (final node in _document) {
      final length = node is TextNode ? node.text.length : 0;
      if (remaining <= length) {
        return DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: remaining, affinity: affinity),
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

  void _normalizeEdit(
    EditContext context,
    RequestDispatcher dispatcher,
    List<EditEvent> changes,
  ) {
    // A multiline IME replacement or a soft newline can put a literal
    // newline inside a Super Editor node. Split it before layout or IME
    // serialization so all insertion paths have the same paragraph model.
    final changedIds = changes
        .whereType<DocumentEdit>()
        .map((event) => event.change)
        .whereType<NodeDocumentChange>()
        .map((change) => change.nodeId)
        .toSet();
    final selection = _absoluteSelection();
    var split = false;
    for (final id in changedIds) {
      final node = _document.getNodeById(id);
      if (node is! ParagraphNode) continue;
      final text = node.text.toPlainText();
      for (
        var offset = text.lastIndexOf('\n');
        offset >= 0;
        offset = offset == 0 ? -1 : text.lastIndexOf('\n', offset - 1)
      ) {
        final newId = Editor.createNodeId();
        dispatcher.execute([
          SplitParagraphRequest(
            nodeId: id,
            splitPosition: TextPosition(offset: offset),
            newNodeId: newId,
            replicateExistingMetadata: false,
          ),
          DeleteContentRequest(
            documentRange: DocumentRange(
              start: DocumentPosition(
                nodeId: newId,
                nodePosition: const TextNodePosition(offset: 0),
              ),
              end: DocumentPosition(
                nodeId: newId,
                nodePosition: const TextNodePosition(offset: 1),
              ),
            ),
          ),
        ]);
        split = true;
      }
    }
    if (split && selection != null) {
      _moveSelection(dispatcher, selection);
    }
    if (changedIds.isNotEmpty) _enforceLength(dispatcher);
  }

  void _enforceLength(RequestDispatcher dispatcher) {
    final limit = widget.maxLength;
    if (limit == null || limit == TextField.noMaxLength) return;
    final text = _join(_document);
    if (text == _knownText || text.characters.length <= limit) return;
    final selection =
        _absoluteSelection() ?? TextSelection.collapsed(offset: text.length);
    final next =
        LengthLimitingTextInputFormatter(
          limit,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
        ).formatEditUpdate(
          widget.controller.value.copyWith(text: _knownText),
          TextEditingValue(text: text, selection: selection),
        );
    if (next.text != text) _replaceText(dispatcher, text, next);
  }

  void _replaceText(
    RequestDispatcher dispatcher,
    String before,
    TextEditingValue after,
  ) {
    // Match whole graphemes so a shared surrogate or combining mark cannot
    // leave an invalid boundary when the replacement changes an emoji.
    final previous = before.characters.toList();
    final updated = after.text.characters.toList();
    var prefix = 0;
    var start = 0;
    while (prefix < math.min(previous.length, updated.length) &&
        previous[prefix] == updated[prefix]) {
      start += previous[prefix++].length;
    }
    var oldTail = previous.length;
    var newTail = updated.length;
    var oldEnd = before.length;
    var newEnd = after.text.length;
    while (oldTail > prefix &&
        newTail > prefix &&
        previous[oldTail - 1] == updated[newTail - 1]) {
      oldEnd -= previous[--oldTail].length;
      newEnd -= updated[--newTail].length;
    }
    final at = _positionAt(start);
    dispatcher.execute([
      if (oldEnd > start)
        DeleteContentRequest(
          documentRange: DocumentRange(start: at, end: _positionAt(oldEnd)),
        ),
      if (newEnd > start)
        PasteEditorRequest(
          content: after.text.substring(start, newEnd),
          pastePosition: at,
        ),
    ]);
    final selection = after.selection.isValid
        ? after.selection
        : TextSelection.collapsed(offset: after.text.length);
    _moveSelection(dispatcher, selection);
  }

  void _moveSelection(RequestDispatcher dispatcher, TextSelection selection) {
    dispatcher.execute([
      ChangeSelectionRequest(
        DocumentSelection(
          base: _positionAt(selection.baseOffset),
          extent: _positionAt(
            selection.extentOffset,
            affinity: selection.affinity,
          ),
        ),
        SelectionChangeType.placeCaret,
        _controllerSelection,
      ),
    ]);
  }

  /// Applies Markdown source edits inside the document's undo history.
  Future<void> _format(NexFormatCommand command) async {
    final value = widget.controller.value;
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final start = selection.start;
    final end = selection.end;
    NexFormattedText? result;
    switch (command) {
      case NexFormatCommand.bold:
        result = NexTextFormatting.toggleInline(
          value.text,
          start,
          end,
          NexInlineFormat.bold,
        );
      case NexFormatCommand.italic:
        result = NexTextFormatting.toggleInline(
          value.text,
          start,
          end,
          NexInlineFormat.italic,
        );
      case NexFormatCommand.mono:
        result = NexTextFormatting.toggleInline(
          value.text,
          start,
          end,
          NexInlineFormat.mono,
        );
      case NexFormatCommand.strikethrough:
        result = NexTextFormatting.toggleInline(
          value.text,
          start,
          end,
          NexInlineFormat.strikethrough,
        );
      case NexFormatCommand.quote:
        result = NexTextFormatting.toggleQuote(value.text, start, end);
      case NexFormatCommand.link:
        final url = await nexAskForLinkUrl(context);
        if (!mounted ||
            url == null ||
            url.isEmpty ||
            widget.controller.text != value.text ||
            widget.readOnly) {
          return;
        }
        result = NexTextFormatting.link(value.text, start, end, url);
      case NexFormatCommand.clear:
        result = NexTextFormatting.clear(value.text, start, end);
    }
    if (result.text == value.text) return;
    final selectionAfter = TextSelection(
      baseOffset: selection.baseOffset > selection.extentOffset
          ? result.end
          : result.start,
      extentOffset: selection.baseOffset > selection.extentOffset
          ? result.start
          : result.end,
    );
    _editor.startTransaction();
    try {
      _replaceText(
        _editor,
        value.text,
        TextEditingValue(text: result.text, selection: selectionAfter),
      );
    } finally {
      _editor.endTransaction();
    }
    setState(() => _formatBarDismissed = true);
  }

  @override
  Widget build(BuildContext context) => _buildEditor(context);
}
