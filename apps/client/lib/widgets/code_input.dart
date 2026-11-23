import 'package:flutter/services.dart';

/// Editing gestures for source fields. Multi-character edits and IME
/// composition pass through so a paste keeps its original whitespace.
class NexCodeInputFormatter extends TextInputFormatter {
  const NexCodeInputFormatter();

  static const _pairs = {'(': ')', '[': ']', '{': '}', '"': '"', "'": "'"};

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (!selection.isValid ||
        !oldValue.composing.isCollapsed ||
        !newValue.composing.isCollapsed ||
        !newValue.selection.isCollapsed) {
      return newValue;
    }
    final start = selection.start;
    final end = selection.end;
    final source = oldValue.text;
    if (end > source.length ||
        newValue.selection.start != start + 1 ||
        newValue.text.length != source.length - (end - start) + 1) {
      return newValue;
    }
    final input = newValue.text[start];
    if (input == '\n') {
      final lineStart = start == 0
          ? 0
          : source.lastIndexOf('\n', start - 1) + 1;
      var indentEnd = lineStart;
      while (indentEnd < start &&
          (source[indentEnd] == ' ' || source[indentEnd] == '\t')) {
        indentEnd++;
      }
      final indent = source.substring(lineStart, indentEnd);
      final newline = source.contains('\r\n') ? '\r\n' : '\n';
      return _replace(source, start, end, '$newline$indent');
    }

    if (start == end &&
        _pairs.containsValue(input) &&
        (start == 0 || source.codeUnitAt(start - 1) != 0x5c) &&
        source.startsWith(input, start)) {
      return oldValue.copyWith(
        selection: TextSelection.collapsed(offset: start + 1),
      );
    }
    final closing = _pairs[input];
    if (closing == null) return newValue;
    final quote = input == closing;
    if (quote && start > 0 && _afterWordOrEscape.hasMatch(source[start - 1])) {
      return newValue;
    }
    if (start == end &&
        end < source.length &&
        !_beforePair.hasMatch(source[end])) {
      return newValue;
    }
    final selected = source.substring(start, end);
    final paired = _replace(source, start, end, '$input$selected$closing');
    return paired.copyWith(
      selection: selection.copyWith(
        baseOffset: selection.baseOffset + 1,
        extentOffset: selection.extentOffset + 1,
      ),
    );
  }

  static final _afterWordOrEscape = RegExp(r'[\w\\]');
  static final _beforePair = RegExp(r'[\s)\]}>,;:]');

  static TextEditingValue _replace(
    String source,
    int start,
    int end,
    String replacement,
  ) => TextEditingValue(
    text: source.replaceRange(start, end, replacement),
    selection: TextSelection.collapsed(offset: start + replacement.length),
  );
}
