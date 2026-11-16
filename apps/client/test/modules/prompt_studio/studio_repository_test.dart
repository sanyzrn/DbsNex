import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/prompt_studio/prompt_model.dart';
import 'package:nex_client/modules/prompt_studio/studio_repository.dart';

import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore store;
  late StudioRepository repo;
  setUp(() async {
    h = await NexTestHarness.create(name: 'prompt_repo_');
    store = NexModuleStore(h.services, 'prompt_studio');
    repo = StudioRepository(store);
  });
  tearDown(() => h.dispose());
  final fields = <String, Object?>{
    'title': 'A',
    'body': 'Hello {{name}}',
    'category': '',
    'notes': '',
  };
  test(
    'single-record revisions preserve unknown fields and keep ten old versions',
    () async {
      await store.put('entry', 'a', {
        ...fields,
        'v': 1,
        'future': {'keep': true},
      });
      for (var i = 0; i < 15; i++) {
        final raw = await store.get('entry', 'a');
        await repo.save('a', raw, {...fields, 'body': 'version $i'});
      }
      final raw = (await store.get('entry', 'a'))!;
      expect(raw['future'], {'keep': true});
      final p = PromptEntry('a', raw);
      expect(p.history.length, 10);
      expect(p.history.first['body'], 'version 13');
    },
  );
  test('stale edits and stale deletes cannot overwrite a later save', () async {
    await repo.save('a', null, fields);
    final old = (await store.get('entry', 'a'))!;
    await repo.save('a', old, {...fields, 'body': 'new'});
    await expectLater(
      repo.save('a', old, fields),
      throwsA(isA<StudioConflict>()),
    );
    await expectLater(
      repo.delete(PromptEntry('a', old)),
      throwsA(isA<StudioConflict>()),
    );
    expect((await store.get('entry', 'a'))!['body'], 'new');
  });
  test('Undo restores the exact raw body but refuses a recreated id', () async {
    await store.put('entry', 'a', {...fields, 'future': 9});
    final old = (await store.get('entry', 'a'))!;
    final raw = await repo.delete(PromptEntry('a', old));
    await repo.undo('a', raw);
    expect(await store.get('entry', 'a'), old);
    await expectLater(repo.undo('a', raw), throwsA(isA<StudioConflict>()));
  });
  test('failed queued operations do not poison later saves', () async {
    await expectLater(
      repo.save('a', {'wrong': true}, fields),
      throwsA(isA<StudioConflict>()),
    );
    await repo.save('a', null, fields);
    expect((await store.list('entry')).length, 1);
    expect(await NexModuleStore(h.services, 'parking').list('entry'), isEmpty);
  });
}
