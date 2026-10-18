import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

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
  test(
    'damaged JSON and timestamps are isolated without losing raw originals',
    () {
      records.put('medicine', 'medicine', 'healthy', {'name': 'Healthy'});
      for (final (id, body, stamp) in [
        ('bad-json', '{broken', '2026-10-18T00:00:00Z'),
        ('bad-shape', '[]', '2026-10-18T00:00:00Z'),
        ('bad-date', '{"name":"Keep"}', 'not-a-date'),
      ]) {
        db.db.execute('INSERT INTO module_records VALUES (?, ?, ?, ?, ?)', [
          'medicine',
          'medicine',
          id,
          body,
          stamp,
        ]);
      }
      expect(records.list('medicine', 'medicine').map((r) => r.id), [
        'healthy',
      ]);
      final recovery = records.list('medicine', '__recovery');
      expect(recovery, hasLength(3));
      expect(
        recovery.map((r) => r.body['rawBody']),
        containsAll(['{broken', '[]', '{"name":"Keep"}']),
      );
      expect(records.list('medicine', 'medicine'), hasLength(1));
      expect(records.list('medicine', '__recovery'), hasLength(3));
      expect(records.list('parking', '__recovery'), isEmpty);
    },
  );

  test('direct read of a damaged row keeps its exact body for recovery', () {
    db.db.execute('INSERT INTO module_records VALUES (?, ?, ?, ?, ?)', [
      'parking',
      'session',
      'bad',
      'null',
      '2026-10-18T00:00:00Z',
    ]);
    expect(records.get('parking', 'session', 'bad'), isNull);
    expect(
      records.list('parking', '__recovery').single.body['rawBody'],
      'null',
    );
  });

  test(
    'binary corruption in a body or metadata preserves bytes and healthy rows',
    () {
      final bytes = Uint8List.fromList([0, 255, 128, 1]);
      records.put('parking', 'session', 'healthy', {'note': 'Keep me'});
      for (final row in <List<Object?>>[
        ['body', bytes, '2026-10-18T00:00:00Z'],
        [bytes, '{"note":"Keep"}', '2026-10-18T00:00:00Z'],
        ['date', '{"note":"Keep"}', bytes],
      ]) {
        db.db.execute('INSERT INTO module_records VALUES (?, ?, ?, ?, ?)', [
          'parking',
          'session',
          ...row,
        ]);
      }
      expect(records.list('parking', 'session').map((r) => r.id), ['healthy']);
      final recovery = records.list('parking', '__recovery');
      expect(recovery, hasLength(3));
      final encoded = {'encoding': 'base64', 'value': base64Encode(bytes)};
      expect(recovery.map((r) => r.body['rawBody']), contains(equals(encoded)));
      expect(recovery.map((r) => r.body['id']), contains(equals(encoded)));
      expect(
        recovery.map((r) => r.body['updatedAt']),
        contains(equals(encoded)),
      );
      expect(records.list('parking', 'session'), hasLength(1));
      expect(records.list('parking', '__recovery'), hasLength(3));
    },
  );
}
