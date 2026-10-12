import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteModuleRecordRepository records;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_modules_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    records = SqliteModuleRecordRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  test('put, get, replace and delete one record', () {
    records.put('parking', 'spot', 'a', {'note': 'B2, pillar 14'});
    expect(records.get('parking', 'spot', 'a')!.body, {
      'note': 'B2, pillar 14',
    });
    records.put('parking', 'spot', 'a', {'note': 'B3', 'floor': -3});
    expect(records.list('parking', 'spot'), hasLength(1));
    expect(records.get('parking', 'spot', 'a')!.body['floor'], -3);
    records.delete('parking', 'spot', 'a');
    expect(records.get('parking', 'spot', 'a'), isNull);
  });

  test('a list is newest first, and one kind only', () {
    records.put('words', 'card', 'old', {}, now: DateTime.utc(2026));
    records.put('words', 'card', 'new', {}, now: DateTime.utc(2026, 2));
    records.put('words', 'deck', 'x', {}, now: DateTime.utc(2026, 3));
    expect(records.list('words', 'card').map((r) => r.id), ['new', 'old']);
  });

  test('one module never sees or deletes another one\'s records', () {
    records.put('parking', 'spot', 'a', {'n': 1});
    records.put('gold', 'spot', 'a', {'n': 2});
    expect(records.get('gold', 'spot', 'a')!.body['n'], 2);
    expect(records.deleteAll('parking'), 1);
    expect(records.count('parking'), 0);
    expect(records.count('gold'), 1);
  });

  test('records survive closing and opening the library', () {
    records.put('parking', 'spot', 'a', {'note': 'here'});
    db.close();
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    records = SqliteModuleRecordRepository(db);
    expect(records.get('parking', 'spot', 'a')!.body['note'], 'here');
  });
}
