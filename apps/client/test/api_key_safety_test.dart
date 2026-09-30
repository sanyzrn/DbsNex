import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A keystore that answers nothing — what Android can do for a launch after a
/// system update or a lock-screen change.
class _Unreadable extends TestFlutterSecureStoragePlatform {
  _Unreadable(super.data);

  final deleted = <String>[];
  Map<String, String>? readOptions;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    readOptions = options;
    throw Exception('keystore unavailable');
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    deleted.add(key);
    return super.delete(key: key, options: options);
  }
}

/// A saved API key must survive a launch where it could not be read.
void main() {
  test('an unreadable key is never deleted by saving an empty field', () async {
    SharedPreferences.setMockInitialValues({'ai.provider': 'openai'});
    final store = _Unreadable({'ai.key.openai': 'sk-kept'});
    FlutterSecureStoragePlatform.instance = store;

    final preferences = await NexPreferences.load();
    expect(preferences.secureStorageUnavailable, isTrue);
    // The screen had nothing to show, so it saves an empty key.
    expect(preferences.aiProvider.apiKey, isEmpty);
    await preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai),
    );

    expect(store.deleted, isNot(contains('ai.key.openai')));
    expect(store.data['ai.key.openai'], 'sk-kept');
    // And the plugin is told not to wipe the store when a read fails.
    expect(store.readOptions?['resetOnError'], 'false');
  });
}
