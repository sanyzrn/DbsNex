import 'dart:async';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import 'nex_caret_movement.dart';
import 'nex_paragraph_editor.dart';
import 'text_format_menu.dart';

/// Shared input for prose and specialised fields (ADR-037).
///
/// Multiline prose uses one paragraph document and one Flutter IME client.
/// Fixed-direction input, code and private clipboard fields use Flutter's
/// native field with their own keyboard and clipboard policies.
class NexTextField extends StatefulWidget {
  const NexTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.style,
    this.textDirection,
    this.monospace = false,
    this.minLines,
    this.maxLines,
    this.expands = false,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.keyboardType = TextInputType.multiline,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.sentences,
    this.onChanged,
    this.inputFormatters,
    this.onSubmitted,
    this.maxLength,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enableIMEPersonalizedLearning = true,
    this.formatting = false,
    this.onCopy,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final TextStyle? style;

  /// A direction the field keeps regardless of what is typed into it.
  ///
  /// Null lets each prose paragraph choose its own direction.
  final TextDirection? textDirection;

  /// Draw a fixed-width face. Code is not prose, and its width is part of
  /// how it reads.
  final bool monospace;

  final int? minLines;

  /// Null grows without limit.
  final int? maxLines;

  /// Fills the height it is given instead of sizing to its text.
  final bool expands;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final TextInputType keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;
  final bool autocorrect;
  final bool enableSuggestions;

  /// False for private fields — the vault — so the keyboard does not learn
  /// from them.
  final bool enableIMEPersonalizedLearning;

  /// Bold, italic and the rest on the selection menu — see
  /// `nexFormatContextMenuBuilder`.
  final bool formatting;

  /// Where Copy and Cut send the selected text instead of the clipboard —
  /// the vault's `PrivateClipboard`, which marks it sensitive and clears it.
  /// Null is the ordinary clipboard. With it set, Share is left off the
  /// selection menu, so what is copied privately cannot leave the app by
  /// the side door.
  final Future<void> Function(String text)? onCopy;

  @override
  State<NexTextField> createState() => _NexTextFieldState();
}

class _NexTextFieldState extends State<NexTextField> {
  /// The formatting menu, made once and kept.
  ///
  /// Not `nexFormatContextMenuBuilder(context)` in `build`: `EditableText`
  /// compares this builder against the previous one **by identity**, and a
  /// fresh closure every rebuild reads as a changed menu. Its answer to that
  /// is to dispose the selection overlay and make a new one after the next
  /// frame — and the selection handles, the magnifier and the toolbar live
  /// in that overlay, with their gesture recognizers. The sheets these fields
  /// sit in rebuild on every keystroke and every frame of the keyboard's
  /// animation, so a handle being dragged was torn away mid-drag.
  late final EditableTextContextMenuBuilder _formatMenu =
      nexFormatContextMenuBuilder(context);

  final _nativeKey = GlobalKey();

  bool _usesParagraphs(NexTextField field) =>
      field.maxLines != 1 &&
      field.textDirection == null &&
      !field.monospace &&
      field.onCopy == null &&
      field.keyboardType == TextInputType.multiline &&
      (field.inputFormatters?.isEmpty ?? true);

  @override
  void didUpdateWidget(NexTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_usesParagraphs(oldWidget) &&
        !_usesParagraphs(widget) &&
        widget.focusNode?.hasFocus == true) {
      // The capture composer keeps its FocusNode when switching to Code.
      // EditableText needs an explicit request because focus was already
      // granted, so it won't get a second focus-change notification.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.focusNode?.hasFocus != true) return;
        _requestNativeKeyboard(_nativeKey.currentContext as Element?);
      });
    }
  }

  void _requestNativeKeyboard(Element? element) {
    if (element is StatefulElement && element.state is EditableTextState) {
      (element.state as EditableTextState).requestKeyboard();
      return;
    }
    element?.visitChildren(_requestNativeKeyboard);
  }

  @override
  Widget build(BuildContext context) {
    if (!_usesParagraphs(widget)) return _flutter(context);

    return NexParagraphEditor(
      controller: widget.controller,
      focusNode: widget.focusNode,
      asField: true,
      style: widget.style,
      decoration: widget.decoration,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      expands: widget.expands,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction ?? TextInputAction.newline,
      textCapitalization: widget.textCapitalization,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      maxLength: widget.maxLength,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      enableIMEPersonalizedLearning: widget.enableIMEPersonalizedLearning,
      formatting: widget.formatting,
    );
  }

  Widget _flutter(BuildContext context) {
    final monoStyle = widget.monospace
        ? NexCodeText.monospaceStyle(
            widget.style ?? Theme.of(context).textTheme.bodyLarge,
          )
        : widget.style;
    Widget field(TextDirection? direction) => TextField(
      key: _nativeKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      decoration: widget.decoration,
      style: monoStyle,
      minLines: widget.expands ? null : widget.minLines,
      maxLines: widget.expands ? null : widget.maxLines,
      expands: widget.expands,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      onChanged: widget.onChanged,
      inputFormatters: widget.inputFormatters,
      onSubmitted: widget.onSubmitted,
      maxLength: widget.maxLength,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.monospace ? false : widget.enableSuggestions,
      // Code is not prose: the keyboard must not turn two hyphens into a
      // dash or straight quotes into curly ones while the person types.
      smartDashesType: widget.monospace ? SmartDashesType.disabled : null,
      smartQuotesType: widget.monospace ? SmartQuotesType.disabled : null,
      enableIMEPersonalizedLearning: widget.enableIMEPersonalizedLearning,
      textDirection: direction,
      textAlign: TextAlign.start,
      textAlignVertical: widget.expands ? TextAlignVertical.top : null,
      // The default paints a double-tapped word's highlight out to the end
      // of the line on right-to-left text.
      selectionWidthStyle: BoxWidthStyle.tight,
      // The handles and the lens are the framework's own — on Android and
      // iOS, from the same laid-out paragraph the field draws. Stated rather
      // than inherited because 2.9.4 removed the native bridge the old
      // editor needed, and a later edit that disables the lens should be
      // visible here. See [NexVisualCaretKeys] for the arrows.
      magnifierConfiguration: TextMagnifier.adaptiveMagnifierConfiguration,
      contextMenuBuilder: widget.onCopy != null
          ? _privateMenu
          : widget.formatting
          ? _formatMenu
          : nexReadingMenu,
    );
    return NexAutoDirection(
      controller: widget.controller,
      direction: widget.textDirection,
      builder: (context, direction) =>
          NexVisualCaretKeys(child: field(direction)),
    );
  }

  Widget _privateMenu(BuildContext context, EditableTextState state) =>
      nexPrivateSelectionMenu(
        state,
        copy: widget.onCopy!,
        onChanged: (text) => widget.onChanged?.call(text),
        canCut: () => mounted && widget.enabled && !widget.readOnly,
      );
}

/// Keep private fields' menu limited to editing commands. Copy and Cut use
/// the caller's private clipboard, including its Android sensitive-clip flag.
Widget nexPrivateSelectionMenu(
  EditableTextState state, {
  required Future<void> Function(String) copy,
  required ValueChanged<String> onChanged,
  required bool Function() canCut,
}) => AdaptiveTextSelectionToolbar.buttonItems(
  anchors: state.contextMenuAnchors,
  buttonItems: [
    for (final item in state.contextMenuButtonItems)
      if (item.type == ContextMenuButtonType.copy ||
          item.type == ContextMenuButtonType.cut)
        ContextMenuButtonItem(
          type: item.type,
          label: item.label,
          onPressed: () {
            if (!state.mounted) return;
            state.hideToolbar();
            unawaited(
              nexPrivateCopy(
                state.widget.controller,
                copy,
                cut: item.type == ContextMenuButtonType.cut,
                onChanged: onChanged,
                canCut: canCut,
              ),
            );
          },
        )
      else if (item.type == ContextMenuButtonType.paste ||
          item.type == ContextMenuButtonType.selectAll)
        item,
  ],
);

/// Copies the selection in [controller] through [copy], and for a cut takes
/// it out of the text once the copy has gone through. The text is left as
/// it was when the copy fails, or when the text changed in the meantime.
Future<void> nexPrivateCopy(
  TextEditingController controller,
  Future<void> Function(String text) copy, {
  required bool cut,
  ValueChanged<String>? onChanged,
  TextSelection? selection,
  bool Function()? canCut,
}) async {
  final value = controller.value;
  final range = selection ?? value.selection;
  if (!range.isValid || range.isCollapsed || range.end > value.text.length) {
    return;
  }
  try {
    await copy(range.textInside(value.text));
  } catch (_) {
    return;
  }
  if (!cut || canCut?.call() == false || controller.value != value) return;
  final text = range.textBefore(value.text) + range.textAfter(value.text);
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: range.start),
  );
  onChanged?.call(text);
}
