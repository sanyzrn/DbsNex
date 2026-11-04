import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nex_client/platform/vault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  VaultEntry entry(String id) => VaultEntry(
    id: id,
    kind: VaultKind.message,
    fields: {'text': id},
    updatedAt: DateTime.utc(2026),
  );
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'legacy draft migrates without rewriting the main vault on typing',
    () async {
      const storage = FlutterSecureStorage();
      final original = jsonEncode(
        VaultSnapshot([entry('saved')], entry('legacy')).toJson(),
      );
      await storage.write(key: VaultStore.storageKey, value: original);
      expect((await VaultStore().read()).draft!.id, 'legacy');
      await VaultStore().saveDraft(entry('new-draft'));
      expect(await storage.read(key: VaultStore.storageKey), original);
      expect((await VaultStore().read()).draft!.id, 'new-draft');
      await VaultStore().save(entry('new-draft'));
      expect((await VaultStore().read()).draft, isNull);
      expect((await VaultStore().read()).entries.map((e) => e.id), [
        'saved',
        'new-draft',
      ]);
    },
  );
  test(
    'draft write does not parse or replace an unavailable main vault',
    () async {
      const storage = FlutterSecureStorage();
      await storage.write(key: VaultStore.storageKey, value: '{broken');
      await VaultStore().saveDraft(entry('recoverable'));
      expect(await storage.read(key: VaultStore.storageKey), '{broken');
      final separate =
          jsonDecode((await storage.read(key: VaultStore.draftKey))!) as Map;
      expect((separate['draft'] as Map)['id'], 'recoverable');
      await expectLater(VaultStore().read(), throwsFormatException);
    },
  );
}
