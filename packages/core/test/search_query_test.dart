import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  test('operators are lifted out and the rest stays a search', () {
    final parsed = parseSearchQuery('tag:work type:link cooler');
    expect(parsed.tagNames, ['work']);
    expect(parsed.types, [NoteType.link]);
    expect(parsed.text, 'cooler');
    expect(parsed.hasFilters, isTrue);
  });

  test('quotes hold a phrase and a tag with a space together', () {
    final parsed = parseSearchQuery('tag:"to read" "the cooler"');
    expect(parsed.tagNames, ['to read']);
    expect(parsed.text, 'the cooler');
  });

  test('the plurals people actually type are understood', () {
    expect(parseSearchQuery('type:photos').types, [NoteType.photo]);
    expect(parseSearchQuery('type:todos').types, [NoteType.checklist]);
    expect(parseSearchQuery('type:VOICE').types, [NoteType.voice]);
  });

  test('a type can be named in Persian', () {
    expect(parseSearchQuery('type:عکس').types, [NoteType.photo]);
    expect(parseSearchQuery('type:صوتی').types, [NoteType.voice]);
    expect(parseSearchQuery('type:لینک').types, [NoteType.link]);
    expect(parseSearchQuery('type:چک‌لیست').types, [NoteType.checklist]);
    // The half-space is folded away, so both spellings are the operator.
    expect(parseSearchQuery('type:فایل‌ها').types, [NoteType.file]);
    // An Arabic-script spelling still names the type.
    expect(parseSearchQuery('type:تصویر').types, [NoteType.photo]);
  });

  // A search box is not a syntax exam. Anything that is not exactly an
  // operator with a value is what the user is looking for.
  test('near-misses stay ordinary search terms', () {
    expect(parseSearchQuery('type:').text, 'type:');
    expect(parseSearchQuery(':work').text, ':work');
    expect(parseSearchQuery('type:banana').text, 'type:banana');
    expect(parseSearchQuery('https://example.com').text, 'https://example.com');
    final mixed = parseSearchQuery('note:me tag:work');
    expect(mixed.text, 'note:me');
    expect(mixed.tagNames, ['work']);
  });

  test('several of the same operator all count', () {
    final parsed = parseSearchQuery('tag:a tag:b type:text type:voice');
    expect(parsed.tagNames, ['a', 'b']);
    expect(parsed.types, [NoteType.text, NoteType.voice]);
    expect(parsed.text, isEmpty);
  });
}
