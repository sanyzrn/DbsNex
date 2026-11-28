part of 'nex_paragraph_editor.dart';

extension _NexParagraphEditorView on _NexParagraphEditorState {
  double _fieldHeight(
    BuildContext context,
    BoxConstraints constraints,
    TextStyle style,
  ) {
    final minLines = widget.minLines ?? 1;
    final maxLines = widget.maxLines;
    final painter = TextPainter(
      textDirection: _resolver.fallback,
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
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
      return totalHeight.clamp(minHeight, maxHeight);
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

  Stylesheet _stylesheetFor(TextStyle style) {
    if (_lastStyle == style && _stylesheet != null) return _stylesheet!;
    _lastStyle = style;
    return _stylesheet = defaultStylesheet.copyWith(
      addRulesAfter: [
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
    );
  }

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
    return Positioned(
      left: 0,
      right: 0,
      top: math.max(0, anchor.top - 44),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: NexSelectionFormatBar(
          labels: {
            NexFormatCommand.bold: l10n.formatBold,
            NexFormatCommand.italic: l10n.formatItalic,
            NexFormatCommand.mono: l10n.formatMono,
            NexFormatCommand.strikethrough: l10n.formatStrikethrough,
            NexFormatCommand.quote: l10n.formatQuote,
            NexFormatCommand.link: l10n.formatLink,
            NexFormatCommand.clear: l10n.formatClear,
          },
          onSelected: _format,
        ),
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
    final stylesheet = _stylesheetFor(style);
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
        componentBuilders: _builders,
        selectionStyle: selectionStyle,
      );
    } else {
      content = SuperEditor(
        editor: _editor,
        focusNode: _focus,
        autofocus: widget.autofocus,
        inputRole: _inputRole,
        scrollController: _scroll,
        documentLayoutKey: _layoutKey,
        shrinkWrap: false,
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
        keyboardActions: [
          _handleEnter,
          _handleHorizontalArrow,
          for (final action in defaultImeKeyboardActions)
            if (action != cmdBToToggleBold && action != cmdIToToggleItalics)
              action,
        ],
        componentBuilders: _builders,
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
    final anchor = showFormatBar ? (_selectionRect() ?? Rect.zero) : null;
    // Keep the editor in the same element when its selection menu opens.
    final bodyWithToolbar = ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [content, if (anchor != null) _formatBar(context, anchor)],
      ),
    );
    if (!_isField) return TextFieldTapRegion(child: bodyWithToolbar);

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
              child: SizedBox(
                width: constraints.maxWidth,
                child: bodyWithToolbar,
              ),
            ),
            _ => bodyWithToolbar,
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
