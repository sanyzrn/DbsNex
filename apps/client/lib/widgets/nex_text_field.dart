import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'text_format_menu.dart';

/// Where a person writes more than one line of their own words.
///
/// **The rule (ADR-037):** every field that takes multi-line user text — a
/// note, a caption, a message, a bio — is a [NexTextField], never a bare
/// `TextField`. `test/text_field_rule_test.dart` fails the build otherwise.
///
/// On Android it is the platform's own editor, an `EditText`, embedded with
/// hybrid composition. Flutter's editor lays a whole field out in one
/// direction: a Persian note with an English line in it put that line's
/// full stop on the wrong end, an `!` after a Persian sentence in an English
/// note sat before it, and the caret and selection handles followed the
/// same scrambled order — so the end of a sentence could not be reached and
/// the handles looked reversed. Android decides direction and alignment per
/// paragraph, from each paragraph's first strong letter, which is what
/// Telegram and every other app built on that editor show: every line in its
/// own direction, aligned to its own side, with the system's handles,
/// magnifier and menu.
///
/// Everywhere else — Windows, and widget tests, which run on the host — it
/// is Flutter's `TextField`, under [NexAutoDirection], as before.
///
/// The [controller] stays the source of truth for the rest of the app: what
/// is typed natively is written back into it, and anything the app writes
/// into it (an AI rewrite, a format, a cleared composer) is sent to the
/// native editor.
class NexTextField extends StatefulWidget {
  const NexTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.style,
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
  /// native selection menu, so what is copied privately cannot leave the
  /// app by the side door.
  final Future<void> Function(String text)? onCopy;

  /// Whether the native editor is used. True on Android; tests that drive
  /// the native protocol set it, and must put it back.
  static bool native = !kIsWeb && Platform.isAndroid;

  static const viewType = 'nex/edit_text';

  @override
  State<NexTextField> createState() => _NexTextFieldState();
}

class _NexTextFieldState extends State<NexTextField> {
  /// The formatting menu for the Flutter editor, made once and kept.
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
  Widget build(BuildContext context) =>
      NexTextField.native ? _NativeField(field: widget) : _flutter(context);

  Widget _flutter(BuildContext context) => NexAutoDirection(
    controller: widget.controller,
    builder: (context, direction) => TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      decoration: widget.decoration,
      style: widget.style,
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
      onSubmitted: widget.onSubmitted,
      maxLength: widget.maxLength,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      enableIMEPersonalizedLearning: widget.enableIMEPersonalizedLearning,
      textDirection: direction,
      textAlign: TextAlign.start,
      textAlignVertical: widget.expands ? TextAlignVertical.top : null,
      // The default paints a double-tapped word's highlight out to the end
      // of the line on right-to-left text.
      selectionWidthStyle: BoxWidthStyle.tight,
      contextMenuBuilder: widget.onCopy != null
          ? _privateMenu
          : widget.formatting
          ? _formatMenu
          : nexReadingMenu,
    ),
  );

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

/// The Android half: an `EditText` in the widget tree, kept in step with
/// [NexTextField.controller] over a channel of its own.
///
/// The protocol, one channel per view (`nex/edit_text/<id>`):
///
/// - from Dart: `setValue` {text, start, end}, `update` {config}, `focus`,
///   `unfocus`;
/// - from Android: `changed` {text, start, end}, `selection` {start, end},
///   `height` {height}, `focus` {focused}, `submit`, `format` {id, start,
///   end}, and — for a field with [NexTextField.onCopy] — `copy` {start,
///   end, cut}.
class _NativeField extends StatefulWidget {
  const _NativeField({required this.field});

  final NexTextField field;

  @override
  State<_NativeField> createState() => _NativeFieldState();
}

class _NativeFieldState extends State<_NativeField> {
  MethodChannel? _channel;
  late TextEditingController _controller = widget.field.controller;
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.field.focusNode ?? (_ownFocus ??= FocusNode());

  /// The value the native editor is known to hold. A controller change that
  /// matches it came from there and is not sent back.
  late TextEditingValue _native = _controller.value;

  /// Set while a value from the native editor is being written into the
  /// controller, so the listener does not echo it.
  bool _fromNative = false;
  bool _focused = false;
  double? _height;
  String? _lastConfig;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onController);
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_NativeField old) {
    super.didUpdateWidget(old);
    if (old.field.controller != widget.field.controller) {
      old.field.controller.removeListener(_onController);
      _controller = widget.field.controller;
      _controller.addListener(_onController);
      _onController();
    }
    if (old.field.focusNode != widget.field.focusNode) {
      (old.field.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onController() {
    if (_fromNative) return;
    final value = _controller.value;
    if (value.text == _native.text && value.selection == _native.selection) {
      return;
    }
    _native = value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    unawaited(
      _channel?.invokeMethod<void>('setValue', {
        'text': value.text,
        'start': selection.start,
        'end': selection.end,
      }),
    );
  }

  /// Focus asked for from Dart — a `requestFocus` on the field's node —
  /// is passed on, keyboard included.
  ///
  /// The field's node only ever holds focus itself when Dart has just asked
  /// for it: once the editor takes focus, the platform view's own node,
  /// inside this one, takes it over (PlatformViewLink). So primary focus
  /// here always means "focus the editor", even when it already was — a
  /// `requestFocus` on a focused composer takes focus from the platform
  /// view's node, and that clears the editor's.
  void _onFocus() {
    if (_focus.hasPrimaryFocus) {
      unawaited(_channel?.invokeMethod<void>('focus'));
    } else if (!_focus.hasFocus && _focused) {
      unawaited(_channel?.invokeMethod<void>('unfocus'));
    }
  }

  Future<dynamic> _onNative(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    switch (call.method) {
      case 'changed':
        final text = args['text']! as String;
        final value = TextEditingValue(
          text: text,
          selection: _selection(args, text.length),
        );
        final textChanged = text != _controller.text;
        final emptiness = text.isEmpty != _controller.text.isEmpty;
        _native = value;
        _fromNative = true;
        try {
          _controller.value = value;
        } finally {
          _fromNative = false;
        }
        if (textChanged) widget.field.onChanged?.call(text);
        // The decoration's label sits inside an empty field and
        // floats above a filled one, and the counter counts.
        if ((emptiness || widget.field.maxLength != null) && mounted) {
          setState(() {});
        }
      case 'selection':
        final value = _controller.value.copyWith(
          selection: _selection(args, _controller.text.length),
          composing: TextRange.empty,
        );
        _native = value;
        _fromNative = true;
        try {
          _controller.value = value;
        } finally {
          _fromNative = false;
        }
      case 'height':
        final height = (args['height']! as num).toDouble();
        if (height != _height && mounted) setState(() => _height = height);
      case 'focus':
        final focused = args['focused'] == true;
        if (focused == _focused) return;
        _focused = focused;
        // Not a `requestFocus` here: the platform view's own node already
        // took focus as the editor did, and asking for this one would take
        // it back from that node — which clears the editor's focus again.
        // The one case to act on is the editor losing focus while Dart
        // still wants it here (the clear above raced a `focus`).
        if (!focused && _focus.hasPrimaryFocus) {
          unawaited(_channel?.invokeMethod<void>('focus'));
        }
        if (mounted) setState(() {});
      case 'copy':
        final copy = widget.field.onCopy;
        if (copy == null) return;
        await nexPrivateCopy(
          _controller,
          copy,
          cut: args['cut'] == true,
          onChanged: widget.field.onChanged,
          selection: _selection(args, _controller.text.length),
        );
      case 'submit':
        widget.field.onSubmitted?.call(_controller.text);
      case 'format':
        if (!mounted) return;
        final value = _controller.value.copyWith(
          selection: _selection(args, _controller.text.length),
        );
        final formatted = await nexApplyFormat(
          context,
          args['id']! as String,
          value,
        );
        if (formatted == null || !mounted) return;
        _controller.value = formatted;
        widget.field.onChanged?.call(formatted.text);
    }
  }

  static TextSelection _selection(Map<String, Object?> args, int length) {
    final start = ((args['start'] as int?) ?? length).clamp(0, length);
    final end = ((args['end'] as int?) ?? start).clamp(0, length);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  /// Everything about the editor that is not its text.
  Map<String, Object?> _config(BuildContext context) {
    final field = widget.field;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodyLarge!.merge(field.style);
    final enabled = field.enabled;
    final textColor = (style.color ?? scheme.onSurface).withValues(
      alpha: enabled ? null : 0.38,
    );
    final hintColor =
        field.decoration.hintStyle?.color ??
        theme.inputDecorationTheme.hintStyle?.color ??
        scheme.onSurfaceVariant;
    final selection =
        theme.textSelectionTheme.selectionColor ??
        scheme.primary.withValues(alpha: 0.35);
    final action = field.textInputAction;
    // The app's own text size and the system's, as every Flutter text in
    // the app gets them.
    final scaler = MediaQuery.textScalerOf(context);
    final fontSize = style.fontSize ?? 16;
    // A label resting inside an empty field stands where the hint would be;
    // the hint shows once the label has moved up out of its way.
    final labelInside =
        (field.decoration.labelText != null ||
            field.decoration.label != null) &&
        _controller.text.isEmpty &&
        !_focused &&
        field.decoration.floatingLabelBehavior != FloatingLabelBehavior.always;
    return {
      'hint': labelInside ? null : field.decoration.hintText,
      'fontSize': scaler.scale(fontSize),
      'lineHeight': style.height,
      'letterSpacing': style.letterSpacing == null
          ? null
          : scaler.scale(fontSize) / fontSize * style.letterSpacing!,
      'textColor': textColor.toARGB32(),
      'hintColor': hintColor.toARGB32(),
      'selectionColor': selection.toARGB32(),
      'accentColor': scheme.primary.toARGB32(),
      'minLines': field.expands ? 0 : (field.minLines ?? 1),
      'maxLines': field.expands ? 0 : (field.maxLines ?? 0),
      'expands': field.expands,
      'imeAction': switch (action) {
        TextInputAction.send => 'send',
        TextInputAction.done => 'done',
        TextInputAction.search => 'search',
        TextInputAction.go => 'go',
        TextInputAction.next => 'next',
        _ => 'newline',
      },
      'keyboard': switch (field.keyboardType.index) {
        2 => 'number',
        3 => 'phone',
        5 => 'email',
        6 => 'url',
        _ => 'text',
      },
      'capitalization': field.textCapitalization.name,
      'autocorrect': field.autocorrect,
      'suggestions': field.enableSuggestions,
      'incognito': !field.enableIMEPersonalizedLearning,
      'enabled': enabled,
      'readOnly': field.readOnly,
      'maxLength': field.maxLength ?? 0,
      'autofocus': field.autofocus,
      'privateCopy': field.onCopy != null,
      'rtl': Directionality.of(context) == TextDirection.rtl,
      'formats': field.formatting
          ? [
              for (final command in nexFormatCommands(
                AppLocalizations.of(context),
              ))
                {'id': command.id, 'label': command.label},
            ]
          : const <Map<String, String>>[],
    };
  }

  @override
  Widget build(BuildContext context) {
    final config = _config(context);
    final encoded = jsonEncode(config);
    if (_lastConfig != null && encoded != _lastConfig) {
      unawaited(_channel?.invokeMethod<void>('update', config));
    }
    _lastConfig = encoded;
    final field = widget.field;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge!.merge(field.style);
    // Until the editor has measured itself, the height its minimum lines
    // will need.
    final fallback =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 16) *
        (style.height ?? 1.4) *
        (field.minLines ?? 1);
    final view = PlatformViewLink(
      viewType: NexTextField.viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        // Every touch on the editor is the editor's: a drag selects or
        // scrolls the text, it does not move the sheet around it.
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (params) {
        final channel = MethodChannel('nex/edit_text/${params.id}')
          ..setMethodCallHandler(_onNative);
        _channel = channel;
        final value = _controller.value;
        final selection = value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
        _native = value;
        return PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: NexTextField.viewType,
            layoutDirection: Directionality.of(context),
            creationParams: {
              ...config,
              'text': value.text,
              'start': selection.start,
              'end': selection.end,
            },
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
      },
    );
    final decoration = field.decoration
        .applyDefaults(theme.inputDecorationTheme)
        // The editor draws the hint itself, in the hint's own direction;
        // the decoration keeps everything around it.
        .copyWith(
          hintText: '',
          // The count a Flutter field shows under itself when it has a
          // limit, unless the decoration says otherwise.
          counterText:
              field.decoration.counterText ??
              (field.maxLength == null
                  ? ''
                  : '${_controller.text.characters.length}/${field.maxLength}'),
        );
    // In Flutter's text-field tap group, as every TextField is: a touch on
    // it while the keyboard is up is a touch on the field, not one that
    // only puts the keyboard away (NexKeyboardDismisser).
    return TextFieldTapRegion(
      child: Focus(
        focusNode: _focus,
        skipTraversal: true,
        child: InputDecorator(
          decoration: decoration,
          isFocused: _focused,
          isEmpty: _controller.text.isEmpty,
          expands: field.expands,
          child: field.expands
              ? view
              : SizedBox(height: math.max(_height ?? fallback, 1), child: view),
        ),
      ),
    );
  }
}
