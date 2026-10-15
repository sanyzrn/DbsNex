/// The fields a word is written into. A headword follows its own script
/// and is laid out per-direction; the meaning, example and note are the
/// module's stand-ins for the platform's `NexTextField` (multi-line,
/// per-paragraph direction — the real editor is a Platform request in the
/// README); the language and tag are one-liners that follow the typing.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_strings.dart';

/// The word itself: big, and in the direction its own script implies —
/// an English headword stays left-to-right inside a Persian interface.
class WordsWordField extends StatelessWidget {
  const WordsWordField({
    super.key,
    required this.controller,
    this.fieldKey,
    this.focusNode,
  });
  final FocusNode? focusNode;

  final TextEditingController controller;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NexAutoDirection(
      controller: controller,
      builder: (context, direction) => TextField(
        key: fieldKey ?? const ValueKey('words-field-headword'),
        controller: controller,
        focusNode: focusNode,
        textDirection: direction,
        style: theme.textTheme.headlineSmall,
        decoration: InputDecoration(
          labelText: wordsStrings(context, 'wordLabel'),
          counterText: '',
        ),
      ),
    );
  }
}

/// A one-line field that follows the typed script.
class WordsAutoField extends StatelessWidget {
  const WordsAutoField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => NexAutoDirection(
    controller: controller,
    builder: (context, _) => TextField(
      key: fieldKey,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
      ),
    ),
  );
}

/// The multi-line stand-in: a real local editor built on `EditableText`
/// with its own focus and decoration — the same shape the platform's
/// `NexTextField` uses off-Android (a field under [NexAutoDirection]).
/// The platform's own editor, with per-paragraph direction and the
/// system's handles, is a Platform request in the README.
class WordsNoteField extends StatefulWidget {
  const WordsNoteField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.fieldKey,
    this.minLines = 2,
    this.maxLines,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final Key? fieldKey;
  final int minLines;
  final int? maxLines;

  @override
  State<WordsNoteField> createState() => _WordsNoteFieldState();
}

class _WordsNoteFieldState extends State<WordsNoteField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NexAutoDirection(
      controller: widget.controller,
      builder: (context, direction) => InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          alignLabelWithHint: true,
          counterText: '',
        ),
        isFocused: _focus.hasFocus,
        isEmpty: widget.controller.text.isEmpty,
        child: EditableText(
          key: widget.fieldKey,
          controller: widget.controller,
          focusNode: _focus,
          style: theme.textTheme.bodyLarge ?? const TextStyle(),
          cursorColor: theme.colorScheme.primary,
          backgroundCursorColor: theme.colorScheme.onSurfaceVariant,
          maxLines: widget.maxLines,
          minLines: widget.minLines,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textDirection: direction,
        ),
      ),
    );
  }
}
