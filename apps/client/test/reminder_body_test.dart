import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/reminders.dart';

/// A reminder's title is the note's first line; what it says under the
/// title is the rest of the note, never the same words again (2.8.1). A
/// one-line note read twice, with blank lines between, on a phone whose
/// language ran the other way.
void main() {
  test('a one-line note is its title alone', () {
    expect(NexReminders.bodyBeyond('claude ریست شد', 'claude ریست شد'), isNull);
  });

  test('a longer note says what comes after its first line', () {
    expect(
      NexReminders.bodyBeyond('Groceries', 'Groceries\nmilk\nbread'),
      'milk bread',
    );
  });

  test('a first line cut short for the title is still said in full', () {
    final first = 'word ' * 20;
    final title = '${first.trim().substring(0, 60)}…';
    expect(NexReminders.bodyBeyond(title, first.trim()), first.trim());
  });

  test('an empty note says nothing', () {
    expect(NexReminders.bodyBeyond('Nex', ''), isNull);
  });
}
