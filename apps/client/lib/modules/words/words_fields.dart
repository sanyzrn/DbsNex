/// The fields a word is written into. A headword follows its own script
/// and is laid out per-direction; the meaning, example and note are the
/// shared `NexTextField` (multi-line,
/// per-paragraph direction on Android); the language and tag are one-liners that follow the typing.
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

/// Multiline text uses Nex's shared platform editor.
class WordsNoteField extends StatelessWidget {
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
  Widget build(BuildContext context) => NexTextField(
    key: fieldKey,
    controller: controller,
    minLines: minLines,
    maxLines: maxLines,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      counterText: '',
    ),
  );
}
