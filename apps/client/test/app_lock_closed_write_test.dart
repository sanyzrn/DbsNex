import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// The lock's closed/open flag is written on every launch, every lock and
/// every unlock — and on every preference refresh while the lock is off,
/// which was the common case paying a disk flush to say what the store
/// already said. The setter skips a write that would change nothing.
class _CountingStore extends InMemorySharedPreferencesStore {
  _CountingStore(super.data) : super.withData();

  int setValueCalls = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    setValueCalls++;
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an unchanged lock state is not written again', () async {
    SharedPreferences.setMockInitialValues({'onboarding.complete': true});
    // Seeded the way `setMockInitialValues` seeds its own store: the plugin's
    // reads are prefixed, and `getAll` answers only prefixed keys.
    final store = _CountingStore({'flutter.onboarding.complete': true});
    SharedPreferencesStorePlatform.instance = store;
    final preferences = await NexPreferences.load();
    addTearDown(preferences.dispose);
    final baseline = store.setValueCalls;

    // The store says nothing about the lock, and nothing says it is closed:
    // the launch-time settle of "closed on launch = false" is a no-op.
    expect(preferences.appLockClosed, isFalse);
    await preferences.setAppLockClosed(false);
    expect(
      store.setValueCalls,
      baseline,
      reason: 'writing what is already there',
    );

    // A real change is written exactly once, however often it is repeated.
    await preferences.setAppLockClosed(true);
    expect(store.setValueCalls, baseline + 1);
    await preferences.setAppLockClosed(true);
    expect(store.setValueCalls, baseline + 1);

    // And the read-back still works, which is the point of the flag.
    expect(preferences.appLockClosed, isTrue);
  });
}
