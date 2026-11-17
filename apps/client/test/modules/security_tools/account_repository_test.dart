import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/security_tools/account_model.dart';
import 'package:nex_client/modules/security_tools/account_repository.dart';

import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore store;
  late AccountRepository repo;
  setUp(() async {
    h = await NexTestHarness.create(name: 'security_repo_');
    store = NexModuleStore(h.services, 'security_tools');
    repo = AccountRepository(store);
  });
  tearDown(() => h.dispose());
  test(
    'fresh edits retain unknown fields and untouched unknown check states',
    () async {
      await store.put('account', 'a', {
        'v': 1,
        'label': 'Old',
        'extra': {'keep': true},
        'checks': {'unique': 'future-state', 'other': 42},
      });
      final raw = await store.get('account', 'a');
      await repo.save('a', raw, ' New ', {'mfa': 'done'});
      final saved = (await store.get('account', 'a'))!;
      expect(saved['label'], 'New');
      expect(saved['extra'], {'keep': true});
      expect(saved['checks'], {
        'unique': 'future-state',
        'other': 42,
        'mfa': 'done',
      });
    },
  );
  test(
    'stale save/delete refuse to replace later changes and queue recovers',
    () async {
      await repo.save('a', null, 'Email', {});
      final old = (await store.get('account', 'a'))!;
      await repo.save('a', old, 'Newer', {'mfa': 'done'});
      await expectLater(
        repo.save('a', old, 'Old', {}),
        throwsA(isA<SecurityConflict>()),
      );
      await expectLater(
        repo.delete(SecurityAccount('a', old)),
        throwsA(isA<SecurityConflict>()),
      );
      await repo.save('b', null, 'Other', {});
      expect((await store.get('account', 'a'))!['label'], 'Newer');
      expect((await store.list('account')).length, 2);
    },
  );
  test('Undo restores raw data, refuses a collision and remains namespace isolated', () async {
    await store.put('account', 'a', {'future': true, 'label': 'Email'});
    final raw = (await store.get('account', 'a'))!;
    final snapshot = await repo.delete(SecurityAccount('a', raw));
    await repo.undo('a', snapshot);
    expect(await store.get('account', 'a'), raw);
    await expectLater(
      repo.undo('a', snapshot),
      throwsA(isA<SecurityConflict>()),
    );
    expect(
      await NexModuleStore(h.services, 'parking').list('account'),
      isEmpty,
    );
  });
  test('invalid aliases and status keys never create records', () async {
    for (final label in ['', ' ', 'x' * 61]) {
      await expectLater(repo.save('a', null, label, {}), throwsArgumentError);
    }
    await expectLater(
      repo.save('a', null, 'Email', {'secret': 'password'}),
      throwsArgumentError,
    );
    await expectLater(
      repo.save('a', null, 'Email', {'mfa': 'yes'}),
      throwsArgumentError,
    );
    expect(await store.list('account'), isEmpty);
  });
}
