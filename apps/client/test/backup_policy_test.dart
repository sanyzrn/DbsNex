import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const stampKey = 'backup.last_at_ms';

  Future<BackupPolicy> policyWith(int stampedAt) async {
    SharedPreferences.setMockInitialValues({stampKey: stampedAt});
    return BackupPolicy(await SharedPreferences.getInstance());
  }

  test('a last-backup stamp in the future does not postpone backups', () async {
    final policy = await policyWith(
      DateTime.now().add(const Duration(days: 365)).millisecondsSinceEpoch,
    );
    // A clock that moved backwards — a dead RTC, a network correction, a
    // changed date — used to leave `elapsed` negative and answer "not due"
    // until the clock climbed back past the old stamp.
    expect(await policy.isDue(), isTrue);
  });

  test('a backup inside the interval is not due', () async {
    final policy = await policyWith(
      DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
    expect(await policy.isDue(), isFalse);
  });

  test('a backup older than the interval is due', () async {
    final policy = await policyWith(
      DateTime.now().subtract(const Duration(hours: 13)).millisecondsSinceEpoch,
    );
    expect(await policy.isDue(), isTrue);
  });
}
