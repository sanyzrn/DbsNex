import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';

void main() {
  test('groups typed and restored amounts and keeps the fraction', () {
    final amount = NexMoneyController(text: '2600000.50');
    addTearDown(amount.dispose);
    expect(amount.text, '2,600,000.50');

    amount.value = const TextEditingValue(
      text: '۲۶۰۰۰۰۰٫۵۰',
      selection: TextSelection.collapsed(offset: 10),
    );
    expect(amount.text, '۲٬۶۰۰٬۰۰۰٫۵۰');
    expect(amount.selection.extentOffset, amount.text.length);
  });

  test('middle edits regroup and keep the cursor beside the change', () {
    final amount = NexMoneyController(text: '123456');
    addTearDown(amount.dispose);
    amount.selection = const TextSelection.collapsed(offset: 2);
    amount.value = const TextEditingValue(
      text: '1293,456',
      selection: TextSelection.collapsed(offset: 3),
    );
    expect(amount.text, '1,293,456');
    expect(amount.selection.extentOffset, 4);

    amount.value = const TextEditingValue(
      text: '1,23,456',
      selection: TextSelection.collapsed(offset: 3),
    );
    expect(amount.text, '123,456');
    expect(amount.selection.extentOffset, 2);
  });

  test('a malformed pasted comma stays visible to the validator', () {
    final amount = NexMoneyController(text: '1000');
    addTearDown(amount.dispose);
    amount.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    amount.value = const TextEditingValue(
      text: '1,50',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(amount.text, '1,50');
    expect(nexUngroupMoney(amount.text), '1,50');
  });

  test('forward delete moves through a generated separator', () {
    final amount = NexMoneyController(text: '12345');
    addTearDown(amount.dispose);
    const caret = TextSelection.collapsed(offset: 2);
    amount.selection = caret;
    amount.value = const TextEditingValue(text: '12345', selection: caret);
    expect(amount.text, '12,345');
    expect(amount.selection.extentOffset, 3);
  });

  test('a decimal-comma field still distinguishes the fraction', () {
    final amount = NexMoneyController(text: '12345,678', decimalComma: true);
    addTearDown(amount.dispose);
    expect(amount.text, '12٬345,678');
    expect(nexUngroupMoney(amount.text, decimalComma: true), '12345,678');
    expect(nexUngroupMoney('1,234', decimalComma: true), '1,234');
  });

  test('grouping waits for the keyboard to finish composing', () {
    final amount = NexMoneyController();
    addTearDown(amount.dispose);
    amount.value = const TextEditingValue(
      text: '1234',
      composing: TextRange(start: 0, end: 4),
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(amount.text, '1234');
    amount.clearComposing();
    expect(amount.text, '1,234');
    expect(amount.selection.extentOffset, 5);
  });
}
