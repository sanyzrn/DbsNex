part of 'nex_paragraph_editor.dart';

class _FieldHeightCache {
  const _FieldHeightCache({
    required this.text,
    required this.maxWidth,
    required this.style,
    required this.textScaler,
    required this.locale,
    required this.fallback,
    required this.minLines,
    required this.maxLines,
    required this.maxHeightConstraint,
    required this.height,
  });

  final String text;
  final double maxWidth;
  final TextStyle style;
  final TextScaler textScaler;
  final Locale? locale;
  final TextDirection fallback;
  final int minLines;
  final int? maxLines;
  final double maxHeightConstraint;
  final double height;

  bool matches({
    required String text,
    required double maxWidth,
    required TextStyle style,
    required TextScaler textScaler,
    required Locale? locale,
    required TextDirection fallback,
    required int minLines,
    required int? maxLines,
    required double maxHeightConstraint,
  }) =>
      identical(this.text, text) &&
      this.maxWidth == maxWidth &&
      this.style == style &&
      this.textScaler == textScaler &&
      this.locale == locale &&
      this.fallback == fallback &&
      this.minLines == minLines &&
      this.maxLines == maxLines &&
      this.maxHeightConstraint == maxHeightConstraint;
}

extension _NexParagraphEditorView on _NexParagraphEditorState {
  double _fieldHeight(
    BuildContext context,
    BoxConstraints constraints,
    TextStyle style,
  ) {
    final minLines = widget.minLines ?? 1;
    final maxLines = widget.maxLines;
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final cached = _heightCache;
    if (cached != null &&
        cached.matches(
          text: _knownText,
          maxWidth: constraints.maxWidth,
          style: style,
          textScaler: textScaler,
          locale: locale,
          fallback: _resolver.fallback,
          minLines: minLines,
          maxLines: maxLines,
          maxHeightConstraint: constraints.maxHeight,
        )) {
      return cached.height;
    }
    final painter = TextPainter(
      textDirection: _resolver.fallback,
      textScaler: textScaler,
      locale: locale,
    );
    try {
      painter.text = TextSpan(text: ' ', style: style);
      final preferredLineHeight = painter.preferredLineHeight;
      final minHeight = minLines * preferredLineHeight;
      final maxHeight = math.max(
        minHeight,
        math.min(
          constraints.maxHeight,
          maxLines == null ? double.infinity : maxLines * preferredLineHeight,
        ),
      );
      var totalHeight = 0.0;
      for (final node in _document) {
        if (node is! TextNode) continue;
        painter
          ..text = TextSpan(text: node.text.toPlainText(), style: style)
          ..textDirection = _resolver.directionOf(_document, node)
          ..layout(maxWidth: constraints.maxWidth);
        totalHeight += math.max(painter.height, preferredLineHeight);
        if (totalHeight >= maxHeight) {
          break;
        }
      }
      final measured = totalHeight.clamp(minHeight, maxHeight);
      _heightCache = _FieldHeightCache(
        text: _knownText,
        maxWidth: constraints.maxWidth,
        style: style,
        textScaler: textScaler,
        locale: locale,
        fallback: _resolver.fallback,
        minLines: minLines,
        maxLines: maxLines,
        maxHeightConstraint: constraints.maxHeight,
        height: measured,
      );
      return measured;
    } finally {
      painter.dispose();
    }
  }

  void _submit(TextInputAction action) {
    if (action != widget.textInputAction || action == TextInputAction.newline) {
      return;
    }
    if (action == TextInputAction.done ||
        action == TextInputAction.send ||
        action == TextInputAction.go ||
        action == TextInputAction.search) {
      _focus.unfocus();
    } else if (action == TextInputAction.next) {
      _focus.nextFocus();
    } else if (action == TextInputAction.previous) {
      _focus.previousFocus();
    }
    widget.onSubmitted?.call(widget.controller.text);
  }

  ExecutionInstruction _handleEnter({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    final key = keyEvent.logicalKey;
    if (keyEvent is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        widget.onSubmitted != null &&
        !HardwareKeyboard.instance.isShiftPressed &&
        widget.textInputAction != TextInputAction.newline) {
      _submit(widget.textInputAction);
      return ExecutionInstruction.haltExecution;
    }
    return ExecutionInstruction.continueExecution;
  }

  ExecutionInstruction _handleFormatShortcut({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    if (!widget.formatting || widget.readOnly || !widget.enabled) {
      return ExecutionInstruction.continueExecution;
    }
    if (keyEvent is! KeyDownEvent) {
      return ExecutionInstruction.continueExecution;
    }
    final keyboard = HardwareKeyboard.instance;
    final modifier = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (!modifier || keyboard.isAltPressed || keyboard.isShiftPressed) {
      return ExecutionInstruction.continueExecution;
    }
    final key = keyEvent.logicalKey;
    if (key == LogicalKeyboardKey.keyB) {
      unawaited(_format(NexFormatCommand.bold));
      return ExecutionInstruction.haltExecution;
    }
    if (key == LogicalKeyboardKey.keyI) {
      unawaited(_format(NexFormatCommand.italic));
      return ExecutionInstruction.haltExecution;
    }
    return ExecutionInstruction.continueExecution;
  }

  ExecutionInstruction _handleClipboardShortcut({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    final keyboard = HardwareKeyboard.instance;
    if (keyEvent is! KeyDownEvent ||
        !(keyboard.isControlPressed || keyboard.isMetaPressed) ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed) {
      return ExecutionInstruction.continueExecution;
    }
    switch (keyEvent.logicalKey) {
      case LogicalKeyboardKey.keyX:
        unawaited(_copySelection(cut: true));
      case LogicalKeyboardKey.keyC:
        unawaited(_copySelection(cut: false));
      case LogicalKeyboardKey.keyV:
        unawaited(_pasteClipboard());
      default:
        return ExecutionInstruction.continueExecution;
    }
    _hideToolbars();
    return ExecutionInstruction.haltExecution;
  }

  ExecutionInstruction _handleHorizontalArrow({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    const pass = ExecutionInstruction.continueExecution;
    final key = keyEvent.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if ((keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) ||
        (key != LogicalKeyboardKey.arrowLeft &&
            key != LogicalKeyboardKey.arrowRight) ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return pass;
    }
    final selection = _composer.selection;
    if (selection == null || _composer.composingRegion.value != null) {
      return pass;
    }
    final extent = selection.extent;
    final position = extent.nodePosition;
    final component = editContext.documentLayout.getComponentByNodeId(
      extent.nodeId,
    );
    final node = _document.getNodeById(extent.nodeId);
    if (position is! TextNodePosition || component == null || node == null) {
      return pass;
    }

    Rect rectForCaret(TextPosition caret) =>
        component.getRectForPosition(TextNodePosition.fromTextPosition(caret));

    final forward = key == LogicalKeyboardKey.arrowRight;
    final expand = keyboard.isShiftPressed;

    // Use the first selected paragraph's reading order for both drag directions.
    if (!expand &&
        !selection.isCollapsed &&
        selection.base.nodeId != extent.nodeId) {
      final normalized = selection.normalize(_document);
      final first = _document.getNodeById(normalized.start.nodeId) ?? node;
      final downstream =
          forward ==
          (_resolver.directionOf(_document, first) == TextDirection.ltr);
      final targetPos = downstream ? normalized.end : normalized.start;
      _editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(position: targetPos),
          SelectionChangeType.collapseSelection,
          SelectionReason.userInteraction,
        ),
        const ClearComposingRegionRequest(),
      ]);
      return ExecutionInstruction.haltExecution;
    }

    TextPosition? target;
    if (selection.isCollapsed || expand) {
      target = nexVisualCaretInLayout(
        position,
        forward: forward,
        rectForCaret: rectForCaret,
        positionAt: (offset) {
          final hit = component.getPositionAtOffset(offset);
          return hit is TextNodePosition ? hit : null;
        },
      );
    } else if (selection.base.nodeId == extent.nodeId &&
        selection.base.nodePosition is TextNodePosition) {
      final base = selection.base.nodePosition as TextNodePosition;
      target = nexVisualSelectionInLayout(
        TextSelection(baseOffset: base.offset, extentOffset: position.offset),
        forward: forward,
        rectForCaret: rectForCaret,
      );
    }

    if (target == null) {
      // At a line edge, continue in this paragraph's reading order.
      final downstream =
          forward ==
          (_resolver.directionOf(_document, node) == TextDirection.ltr);
      final moved = downstream
          ? editContext.commonOps.moveCaretDownstream(expand: expand)
          : editContext.commonOps.moveCaretUpstream(expand: expand);
      return moved ? ExecutionInstruction.haltExecution : pass;
    }

    final destination = DocumentPosition(
      nodeId: extent.nodeId,
      nodePosition: TextNodePosition.fromTextPosition(target),
    );
    _editor.execute([
      ChangeSelectionRequest(
        expand
            ? selection.expandTo(destination)
            : DocumentSelection.collapsed(position: destination),
        expand ? SelectionChangeType.pushExtent : SelectionChangeType.pushCaret,
        SelectionReason.userInteraction,
      ),
      const ClearComposingRegionRequest(),
    ]);
    return ExecutionInstruction.haltExecution;
  }

  /// Minimal single-rule stylesheet for plain-text paragraphs.
  ///
  /// Avoids `defaultStylesheet`'s ~15 rich-block rules and attribution styler,
  /// cutting per-paragraph style evaluation cost on long notes.
  Stylesheet _stylesheetFor(TextStyle style) {
    if (_lastStyle == style && _stylesheet != null) return _stylesheet!;
    _lastStyle = style;
    return _stylesheet = Stylesheet(
      rules: [
        StyleRule(
          BlockSelector.all,
          (document, node) => {
            Styles.padding: const CascadingPadding.symmetric(
              horizontal: 0,
              vertical: 0,
            ),
            Styles.textStyle: style,
          },
        ),
      ],
      inlineTextStyler: (attributions, existingStyle) => existingStyle,
    );
  }

  List<ContextMenuButtonItem> _buildSelectionMenuItems(BuildContext context) {
    final selection = _composer.selection;
    final hasExpandedSelection = selection != null && !selection.isCollapsed;
    final canEdit = !widget.readOnly && widget.enabled;
    final items = <ContextMenuButtonItem>[
      if (hasExpandedSelection && canEdit)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          onPressed: () {
            _hideToolbars();
            unawaited(_copySelection(cut: true));
          },
        ),
      if (hasExpandedSelection)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {
            _hideToolbars();
            unawaited(_copySelection(cut: false));
          },
        ),
      if (canEdit)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () {
            _hideToolbars();
            unawaited(_pasteClipboard());
          },
        ),
      if (_knownText.isNotEmpty)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.selectAll,
          onPressed: () {
            _selectAll();
          },
        ),
    ];

    if (widget.formatting && canEdit && hasExpandedSelection) {
      final l10n = Localizations.of<AppLocalizations>(
        context,
        AppLocalizations,
      );
      if (l10n != null) {
        items.addAll(
          nexFormatMenuItems(
            l10n,
            onCommand: (command) {
              _hideToolbars();
              unawaited(_format(command));
            },
          ),
        );
      }
    }
    return items;
  }

  Widget _buildMobileToolbar(
    BuildContext context,
    Key mobileToolbarKey,
    Object focalPoint,
  ) {
    // Super Editor positions the toolbar alongside its selection handles.
    // Give its follower a compact child that fits above or below the selection.
    return ValueListenableBuilder(
      valueListenable: _composer.selectionNotifier,
      builder: (context, _, _) {
        final items = _buildSelectionMenuItems(context);
        if (items.isEmpty) return const SizedBox.shrink();
        final standard = items.where(
          (item) => item.type != ContextMenuButtonType.custom,
        );
        final formatting = items.where(
          (item) => item.type == ContextMenuButtonType.custom,
        );
        final theme = Theme.of(context);
        return Material(
          key: mobileToolbarKey,
          color: theme.colorScheme.surfaceContainerHigh,
          elevation: 5,
          borderRadius: BorderRadius.circular(NexRadius.md),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.max(0, MediaQuery.sizeOf(context).width - 24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    primary: false,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in standard)
                          TextButton(
                            onPressed: item.onPressed,
                            child: Text(
                              AdaptiveTextSelectionToolbar.getButtonLabel(
                                context,
                                item,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (formatting.isNotEmpty)
                  PopupMenuButton<ContextMenuButtonItem>(
                    tooltip: AppLocalizations.of(context).formatMenu,
                    requestFocus: false,
                    onSelected: (item) => item.onPressed?.call(),
                    itemBuilder: (context) => [
                      for (final item in formatting)
                        PopupMenuItem(value: item, child: Text(item.label!)),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDesktopContextMenu(Offset globalPosition) {
    final items = _buildSelectionMenuItems(context);
    if (items.isEmpty) return;
    _contextMenuController.show(
      context: context,
      contextMenuBuilder: (menuContext) =>
          AdaptiveTextSelectionToolbar.buttonItems(
            anchors: TextSelectionToolbarAnchors(primaryAnchor: globalPosition),
            buttonItems: items,
          ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final theme = Theme.of(context);
    final body =
        theme.textTheme.bodyLarge?.merge(widget.style) ??
        widget.style ??
        const TextStyle(fontSize: 16);
    final style = body.copyWith(
      color: widget.enabled
          ? widget.style?.color ?? theme.colorScheme.onSurface
          : theme.disabledColor,
      height: body.height ?? 1.5,
    );
    final direction = Directionality.of(context);
    if (_resolver.fallback != direction || _resolver.directions.isEmpty) {
      _resolver.fallback = direction;
      _resolver.directions = _resolveDirections();
    }
    final highlightColor = theme.colorScheme.primary.withValues(alpha: 0.22);
    _paragraphBuilder
      ..highlightColor = highlightColor
      ..textStyle = style;
    final stylesheet = _stylesheetFor(style);
    // Selection highlights are painted per paragraph via [_NexParagraphHighlight]
    // using `nexLevelSelectionRects` and a single non-overlapping Path fill.
    const selectionStyle = SelectionStyles(
      selectionColor: Colors.transparent,
      highlightEmptyTextBlocks: false,
    );
    final Widget content;
    if (widget.readOnly || !widget.enabled) {
      // No IME connection at all: a key pressed while the document is only
      // being shown has nowhere to arrive, so it cannot edit the text that is
      // about to be replaced.
      content = SuperReader(
        editor: _editor,
        stylesheet: stylesheet,
        componentBuilders: _builders,
        selectionStyle: selectionStyle,
      );
    } else {
      content = SuperEditorIosControlsScope(
        controller: _iosControls,
        child: SuperEditorAndroidControlsScope(
          controller: _androidControls,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapUp: (details) =>
                _showDesktopContextMenu(details.globalPosition),
            child: SuperEditor(
              editor: _editor,
              focusNode: _focus,
              autofocus: widget.autofocus,
              inputRole: _inputRole,
              scrollController: _scroll,
              shrinkWrap: false,
              documentOverlayBuilders: [
                const SuperEditorIosToolbarFocalPointDocumentLayerBuilder(),
                const SuperEditorIosHandlesDocumentLayerBuilder(),
                const SuperEditorAndroidToolbarFocalPointDocumentLayerBuilder(),
                const SuperEditorAndroidHandlesDocumentLayerBuilder(),
                DefaultCaretOverlayBuilder(
                  caretStyle: CaretStyle(
                    width: 2,
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(1),
                  ),
                  displayCaretWithExpandedSelection: false,
                ),
              ],
              imeConfiguration: _NexImeConfiguration(
                inputType: widget.keyboardType,
                capitalization: widget.textCapitalization,
                personalizedLearning: widget.enableIMEPersonalizedLearning,
                enableAutocorrect: widget.autocorrect,
                enableSuggestions: widget.enableSuggestions,
                keyboardBrightness: theme.brightness,
                keyboardActionButton: widget.textInputAction,
              ),
              imeOverrides: _ime,
              keyboardActions: _keyboardActions,
              componentBuilders: _builders,
              stylesheet: stylesheet,
              selectionStyle: selectionStyle,
            ),
          ),
        ),
      );
    }
    final editorBody = ClipRect(child: content);
    if (!_isField) return TextFieldTapRegion(child: editorBody);

    final decorated = ListenableBuilder(
      listenable: _focus,
      builder: (context, child) {
        final text = widget.controller.text;
        final maxLength = widget.maxLength;
        final decoration =
            maxLength == null ||
                widget.decoration.counter != null ||
                widget.decoration.counterText != null
            ? widget.decoration
            : widget.decoration.copyWith(
                counterText: maxLength == TextField.noMaxLength
                    ? '${text.characters.length}'
                    : '${text.characters.length}/$maxLength',
              );
        return InputDecorator(
          decoration: decoration
              .copyWith(enabled: widget.enabled)
              .applyDefaults(InputDecorationTheme.of(context)),
          isEmpty: text.isEmpty,
          isFocused: _focus.hasFocus,
          baseStyle: style,
          textAlignVertical: TextAlignVertical.top,
          child: child,
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Super Editor otherwise treats the nearest vertical scrollable as
          // its own sliver viewport. A field owns its scrolling even inside
          // a form, so isolate its viewport from the form's scroll position.
          final viewport = switch (Scrollable.maybeOf(context)?.axisDirection) {
            AxisDirection.up || AxisDirection.down => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              primary: false,
              child: SizedBox(width: constraints.maxWidth, child: editorBody),
            ),
            _ => editorBody,
          };
          return SizedBox(
            height: widget.expands && constraints.hasBoundedHeight
                ? constraints.maxHeight
                : _fieldHeight(context, constraints, style),
            child: viewport,
          );
        },
      ),
    );
    return Semantics(
      textField: true,
      readOnly: widget.readOnly,
      enabled: widget.enabled,
      value: widget.controller.text,
      onTap: widget.enabled && !widget.readOnly ? _focus.requestFocus : null,
      onSetText: widget.readOnly || !widget.enabled
          ? null
          : (text) {
              _focus.requestFocus();
              _editor.startTransaction();
              try {
                _replaceText(
                  _editor,
                  _knownText,
                  TextEditingValue(
                    text: text,
                    selection: TextSelection.collapsed(offset: text.length),
                  ),
                );
              } finally {
                _editor.endTransaction();
              }
            },
      child: TextFieldTapRegion(
        child: GestureDetector(
          // The field's padding and outline also bring up the keyboard.
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          onTap: widget.enabled && !widget.readOnly
              ? _focus.requestFocus
              : null,
          child: decorated,
        ),
      ),
    );
  }
}

/// Paints a single non-overlapping, row-levelled selection highlight behind a
/// [TextComponent] so mixed Persian/Latin runs and line-height multipliers
/// never produce overlapping alpha bands or jagged box heights.
class _NexParagraphHighlight extends StatelessWidget {
  const _NexParagraphHighlight({
    required this.text,
    required this.style,
    required this.textDirection,
    required this.textAlign,
    required this.selection,
    required this.color,
    required this.child,
  });

  final String text;
  final TextStyle style;
  final TextDirection textDirection;
  final TextAlign textAlign;
  final TextSelection selection;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NexParagraphHighlightPainter(
        text: text,
        style: style,
        textDirection: textDirection,
        textAlign: textAlign,
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        selection: selection,
        color: color,
      ),
      child: child,
    );
  }
}

class _NexParagraphHighlightPainter extends CustomPainter {
  _NexParagraphHighlightPainter({
    required this.text,
    required this.style,
    required this.textDirection,
    required this.textAlign,
    required this.textScaler,
    required this.locale,
    required this.selection,
    required this.color,
  });

  final String text;
  final TextStyle style;
  final TextDirection textDirection;
  final TextAlign textAlign;
  final TextScaler textScaler;
  final Locale? locale;
  final TextSelection selection;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty || selection.isCollapsed || size.width <= 0) return;
    final clamped = TextSelection(
      baseOffset: selection.baseOffset.clamp(0, text.length),
      extentOffset: selection.extentOffset.clamp(0, text.length),
    );
    if (clamped.isCollapsed) return;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textAlign: textAlign,
      textScaler: textScaler,
      locale: locale,
    );
    try {
      painter.layout(minWidth: size.width, maxWidth: size.width);
      final boxes = painter.getBoxesForSelection(
        clamped,
        boxHeightStyle: BoxHeightStyle.tight,
        boxWidthStyle: BoxWidthStyle.tight,
      );
      if (boxes.isEmpty) return;
      final rects = nexLevelSelectionRects([
        for (final box in boxes) box.toRect(),
      ]);
      if (rects.isEmpty) return;
      final path = Path();
      for (final rect in rects) {
        path.addRect(rect);
      }
      canvas.drawPath(path, Paint()..color = color);
    } finally {
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(_NexParagraphHighlightPainter old) =>
      old.text != text ||
      old.style != style ||
      old.textDirection != textDirection ||
      old.textAlign != textAlign ||
      old.textScaler != textScaler ||
      old.locale != locale ||
      old.selection != selection ||
      old.color != color;
}

class _NexImeActions extends DeltaTextInputClientDecorator {
  _NexImeActions(this.onAction);

  final ValueChanged<TextInputAction> onAction;

  @override
  void performAction(TextInputAction action) {
    super.performAction(action);
    onAction(action);
  }
}

class _NexImeConfiguration extends SuperEditorImeConfiguration {
  const _NexImeConfiguration({
    required this.inputType,
    required this.capitalization,
    required this.personalizedLearning,
    required super.enableAutocorrect,
    required super.enableSuggestions,
    required super.keyboardBrightness,
    required super.keyboardActionButton,
  });

  final TextInputType inputType;
  final TextCapitalization capitalization;
  final bool personalizedLearning;

  @override
  TextInputConfiguration toTextInputConfiguration({required int viewId}) =>
      super
          .toTextInputConfiguration(viewId: viewId)
          .copyWith(
            inputType: inputType,
            textCapitalization: capitalization,
            enableIMEPersonalizedLearning: personalizedLearning,
          );

  @override
  bool operator ==(Object other) =>
      other is _NexImeConfiguration &&
      super == other &&
      inputType == other.inputType &&
      capitalization == other.capitalization &&
      personalizedLearning == other.personalizedLearning;

  @override
  int get hashCode => Object.hash(
    super.hashCode,
    inputType,
    capitalization,
    personalizedLearning,
  );
}
