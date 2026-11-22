import 'package:flutter/widgets.dart';

const _digit = '[0-9۰-۹٠-٩]';
final _easternDigit = RegExp('[۰-۹٠-٩]');
final _groupMark = RegExp('[,٬]');
final _arabicGroupMark = RegExp('٬');
final _groupedAmount = _groupedPattern('[,٬]', '[.٫]');
final _commaDecimalAmount = _groupedPattern('٬', '[.,٫]');
final _plainAmount = _plainPattern('[.٫]');
final _plainCommaDecimal = _plainPattern('[.,٫]');

RegExp _groupedPattern(String grouping, String decimal) => RegExp(
  '^[+−-]?$_digit{1,3}(?:$grouping$_digit{3})+(?:$decimal$_digit*)?\$',
);

RegExp _plainPattern(String decimal) =>
    RegExp('^([+−-]?)($_digit*)($decimal$_digit*)?\$');

/// Removes correctly placed thousands marks. Malformed groups still reach
/// the module's validator, so a decimal comma cannot silently turn into money.
String nexUngroupMoney(String input, {bool decimalComma = false}) {
  final text = input.trim();
  final pattern = decimalComma ? _commaDecimalAmount : _groupedAmount;
  if (!pattern.hasMatch(text)) return input;
  return text.replaceAll(decimalComma ? _arabicGroupMark : _groupMark, '');
}

/// Keeps money readable on edit, restore and unit switches. The module still
/// validates the sign, range and fraction for its own currency.
class NexMoneyController extends TextEditingController {
  NexMoneyController({String? text, this.decimalComma = false}) {
    if (text != null) this.text = text;
  }

  // A field that already accepts decimal commas needs a distinct group mark.
  final bool decimalComma;

  @override
  set value(TextEditingValue next) {
    final previous = value;
    if (!next.composing.isCollapsed ||
        (previous.text == next.text && previous.composing.isCollapsed)) {
      super.value = next;
      return;
    }
    final text = next.text;
    final marks = decimalComma ? _arabicGroupMark : _groupMark;
    var ungrouped = nexUngroupMoney(text, decimalComma: decimalComma);
    if (ungrouped == text &&
        next.selection.isValid &&
        nexUngroupMoney(previous.text, decimalComma: decimalComma) !=
            previous.text) {
      // A keystroke can shift an existing group. Ignore the marks carried
      // over from the previous text, while keeping any newly pasted marks.
      var start = 0;
      var end = text.length;
      var oldEnd = previous.text.length;
      final selection = previous.selection;
      final prefixLimit = selection.isValid ? selection.start : oldEnd;
      final suffixLimit = selection.isValid ? selection.end : 0;
      while (start < end &&
          start < prefixLimit &&
          text[start] == previous.text[start]) {
        start++;
      }
      while (end > start &&
          oldEnd > start &&
          oldEnd > suffixLimit &&
          text[end - 1] == previous.text[oldEnd - 1]) {
        end--;
        oldEnd--;
      }
      ungrouped =
          '${text.substring(0, start).replaceAll(marks, '')}'
          '${text.substring(start, end)}'
          '${text.substring(end).replaceAll(marks, '')}';
    }
    final match = (decimalComma ? _plainCommaDecimal : _plainAmount).firstMatch(
      ungrouped,
    );
    if (match == null) {
      super.value = next;
      return;
    }
    final whole = match[2]!;
    final mark = decimalComma || _easternDigit.hasMatch(ungrouped) ? '٬' : ',';
    final grouped = StringBuffer(match[1]!);
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(mark);
      grouped.write(whole[i]);
    }
    grouped.write(match[3] ?? '');
    final formatted = grouped.toString();
    if (formatted == text) {
      super.value = next;
      return;
    }
    if (!next.selection.isValid) {
      super.value = next.copyWith(text: formatted, composing: TextRange.empty);
      return;
    }
    final caret = next.selection.extentOffset;
    if (next.selection.isCollapsed &&
        next.selection == previous.selection &&
        formatted == previous.text &&
        formatted.length == text.length + 1 &&
        caret < formatted.length &&
        formatted[caret] == mark) {
      // Delete moved through a separator that grouping immediately restored.
      super.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: caret + 1),
      );
      return;
    }

    int offsetOf(int offset) {
      var remaining = text.substring(0, offset).replaceAll(marks, '').length;
      var index = 0;
      while (remaining > 0 && index < formatted.length) {
        if (formatted[index] != mark) remaining--;
        index++;
      }
      return index;
    }

    super.value = next.copyWith(
      text: formatted,
      selection: next.selection.copyWith(
        baseOffset: offsetOf(next.selection.baseOffset),
        extentOffset: offsetOf(next.selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }
}
