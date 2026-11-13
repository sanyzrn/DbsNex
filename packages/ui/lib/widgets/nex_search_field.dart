import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';

import '../tokens/nex_text_direction.dart';
import '../tokens/nex_tokens.dart';

/// Where a [NexSearchField] sits, which decides only its ground.
enum NexSearchFieldGround {
  /// On a page or a sheet: the theme's filled field and outline.
  page,

  /// Inside a surface that already draws the box (Settings' search card): no
  /// fill and no resting line of its own, so there is one shape, not two. The
  /// focus ring stays.
  surface,
}

/// The one search box (2.6.27, docs/26-ui-consistency.md, text entry).
///
/// Every list that could be filtered drew its own: a `TextField` with a
/// search icon, its own clear button or none, a different tooltip on it, its
/// own idea of direction. They looked alike and behaved differently. This is
/// the shared one, and the differences that are real are options:
///
/// - **Direction follows what is typed**, Persian from the right and Latin
///   from the left, unless [textDirection] fixes it — a model id is always
///   left to right.
/// - **Clear** appears once there is text and empties it in one tap. It calls
///   [onChanged] with the empty string, so a filtered list resets at once
///   rather than waiting for the next keystroke.
/// - **[private]** turns off suggestions, autocorrect and the keyboard's
///   learning, for the vault: what someone searches for there is as private
///   as what they keep.
/// - **[ground]** draws it on a page or inside a surface that is already the
///   box.
///
/// The timeline's own search, the pill in the header, is the deliberate
/// exception: it is a header that becomes a field, not a field.
class NexSearchField extends StatefulWidget {
  const NexSearchField({
    super.key,
    required this.controller,
    this.fieldKey,
    this.hintText,
    this.labelText,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.clearable = true,
    this.private = false,
    this.dense = false,
    this.textDirection,
    this.textInputAction = TextInputAction.search,
    this.ground = NexSearchFieldGround.page,
    this.contextMenuBuilder,
  });

  final TextEditingController controller;

  /// Put on the inner [TextField], where tests and other finders look.
  final Key? fieldKey;
  final String? hintText;
  final String? labelText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  /// Whether a clear button appears once there is text.
  final bool clearable;

  /// No suggestions, autocorrect or keyboard learning.
  final bool private;
  final bool dense;

  /// Fixed direction; null follows the text.
  final TextDirection? textDirection;
  final TextInputAction textInputAction;
  final NexSearchFieldGround ground;
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  @override
  State<NexSearchField> createState() => _NexSearchFieldState();
}

class _NexSearchFieldState extends State<NexSearchField> {
  late bool _empty = widget.controller.text.isEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_watch);
  }

  @override
  void didUpdateWidget(NexSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_watch);
    widget.controller.addListener(_watch);
    _empty = widget.controller.text.isEmpty;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_watch);
    super.dispose();
  }

  /// Rebuilds when the box goes from empty to not, never per keystroke or
  /// per selection move: the controller notifies for both.
  void _watch() {
    final empty = widget.controller.text.isEmpty;
    if (empty != _empty) setState(() => _empty = empty);
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
  }

  InputDecoration _decoration(BuildContext context) {
    final clear = widget.clearable && !_empty && widget.enabled
        ? IconButton(
            tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
            icon: const Icon(Icons.close),
            onPressed: _clear,
          )
        : null;
    final decoration = InputDecoration(
      isDense: widget.dense,
      hintText: widget.hintText,
      labelText: widget.labelText,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: clear,
    );
    if (widget.ground == NexSearchFieldGround.page) return decoration;
    final scheme = Theme.of(context).colorScheme;
    const quiet = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(NexRadius.lg)),
      borderSide: BorderSide.none,
    );
    return decoration.copyWith(
      filled: false,
      border: quiet,
      enabledBorder: quiet,
      disabledBorder: quiet,
      focusedBorder: quiet.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: nexFocusRingWidth),
      ),
    );
  }

  Widget _field(BuildContext context, TextDirection? direction) => TextField(
    key: widget.fieldKey,
    controller: widget.controller,
    focusNode: widget.focusNode,
    autofocus: widget.autofocus,
    enabled: widget.enabled,
    textDirection: widget.textDirection ?? direction,
    textAlign: TextAlign.start,
    // A word's own width, as the app's other fields select (not the line's).
    selectionWidthStyle: BoxWidthStyle.tight,
    textInputAction: widget.textInputAction,
    autocorrect: !widget.private,
    enableSuggestions: !widget.private,
    enableIMEPersonalizedLearning: !widget.private,
    contextMenuBuilder: widget.contextMenuBuilder ?? _defaultMenu,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
    decoration: _decoration(context),
  );

  static Widget _defaultMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) => AdaptiveTextSelectionToolbar.editableText(
    editableTextState: editableTextState,
  );

  @override
  Widget build(BuildContext context) => widget.textDirection != null
      ? _field(context, widget.textDirection)
      : NexAutoDirection(controller: widget.controller, builder: _field);
}
