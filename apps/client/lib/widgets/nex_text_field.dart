import 'dart:async';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import 'nex_caret_movement.dart';
import 'text_format_menu.dart';

/// Where a person writes more than one line of their own words.
///
/// **The rule (ADR-037):** every field that takes multi-line user text — a
/// note, a caption, a message, a bio — is a [NexTextField], never a bare
/// `TextField`. `test/text_field_rule_test.dart` fails the build otherwise.
///
/// It is Flutter's own editor on every platform — Android included, since
/// 2.9.4. Until then Android embedded the platform's own `EditText` as a
/// texture layer, because it lays each paragraph out in its own direction,
/// from its first strong letter, which a single `TextField` cannot do for a
/// whole field at once. But a form of embedded editors hands its keyboard
/// from one platform-view input client to the next as focus moves — native
/// to native across Prompt Studio's and Family Fund's forms, native to
/// Flutter from Habits' note to its name — and every such handoff passes
/// through the engine's client switch, which closes and reopened the
/// keyboard. Three releases of Dart-side coordination (2.9.1, 2.9.2,
/// 2.9.3) could not reach that switch. One editor, owned by the framework,
/// never passes through it: focus moves between [TextField]s stay inside
/// the one input connection Flutter already keeps for the whole app. See
/// `docs/development/nex-2.9.4-keyboard.md`.
///
/// Direction and alignment — the reason the native editor existed — follow
/// the paragraph being written. [NexAutoDirection] lays the field out
/// around the caret's own paragraph, in that paragraph's own direction and
/// on its own side, by the same first-strong rule the platform editor gave
/// each paragraph: the paragraph being typed is always right, and the field
/// turns with the caret. A paragraph whose script differs from the caret's
/// paragraph sits on the caret's paragraph's side until the caret reaches
/// it. Everywhere a note is *read* — the timeline, the reader, every
/// preview — each paragraph keeps its own direction and its own side on
/// every platform, through [NexTextSurface], as before.
///
/// Horizontal arrows are the framework's, with one correction: they move to
/// the caret that is next *on screen* rather than the next in the string, so
/// a right-to-left paragraph moves with the eye and an embedded run of the
/// other script keeps its own direction — see `NexVisualCaretKeys`. The
/// selection handles and the lens are the framework's own, enabled on the
/// mobile platforms, and resolve against the same paragraph direction.
///
/// The [controller] stays the source of truth for the rest of the app, on
/// every platform alike. There is no channel, no second copy of the text,
/// and nothing to fall out of step: what is typed is in the controller the
/// frame it is typed, and an AI rewrite, a format, a cleared composer
/// written into the controller is in the editor the same frame.
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
  /// Null is the ordinary rule — the field follows the paragraph the caret
  /// is in, each in its own direction, through [NexAutoDirection]. Code is
  /// the one field that is always left to right, even in a Persian
  /// interface and even when its comments are Persian.
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

  @override
  Widget build(BuildContext context) => _flutter(context);

  Widget _flutter(BuildContext context) {
    final monoStyle = widget.monospace
        ? NexCodeText.monospaceStyle(
            widget.style ?? Theme.of(context).textTheme.bodyLarge,
          )
        : widget.style;
    Widget field(TextDirection? direction) => TextField(
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

  /// The platform's menu with Copy and Cut sent through [NexTextField.onCopy].
  Widget _privateMenu(BuildContext context, EditableTextState state) =>
      AdaptiveTextSelectionToolbar.buttonItems(
        anchors: state.contextMenuAnchors,
        buttonItems: [
          for (final item in state.contextMenuButtonItems)
            if (item.type == ContextMenuButtonType.copy ||
                item.type == ContextMenuButtonType.cut)
              ContextMenuButtonItem(
                type: item.type,
                label: item.label,
                onPressed: () {
                  state.hideToolbar();
                  unawaited(
                    nexPrivateCopy(
                      widget.controller,
                      widget.onCopy!,
                      cut: item.type == ContextMenuButtonType.cut,
                      onChanged: widget.onChanged,
                    ),
                  );
                },
              )
            else if (item.type != ContextMenuButtonType.share)
              item,
        ],
      );
}

/// Copies the selection in [controller] through [copy], and for a cut takes
/// it out of the text once the copy has gone through. The text is left as
/// it was when the copy fails, or when the text changed in the meantime.
@visibleForTesting
Future<void> nexPrivateCopy(
  TextEditingController controller,
  Future<void> Function(String text) copy, {
  required bool cut,
  ValueChanged<String>? onChanged,
  TextSelection? selection,
}) async {
  final value = controller.value;
  final range = selection ?? value.selection;
  if (!range.isValid || range.isCollapsed) return;
  try {
    await copy(range.textInside(value.text));
  } catch (_) {
    return;
  }
  if (!cut || controller.text != value.text) return;
  final text = range.textBefore(value.text) + range.textAfter(value.text);
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: range.start),
  );
  onChanged?.call(text);
}
