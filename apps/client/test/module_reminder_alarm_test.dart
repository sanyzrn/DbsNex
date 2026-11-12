import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the notification plugin, and remembers exactly what it was
/// told — which is the only way to see the payload and the notification
/// details a module reminder actually produced.
class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final pending = <int>{};
  final scheduled = <Map<Symbol, dynamic>>[];

  /// Accepts the request without keeping it, which is what a phone that has
  /// run out of exact alarms does.
  bool dropSchedules = false;

  /// The alarm queue cannot be read at all.
  bool failList = false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final id = invocation.namedArguments[#id] as int?;
    switch (invocation.memberName) {
      case #initialize:
        return Future<bool?>.value(true);
      case #zonedSchedule:
        if (!dropSchedules) pending.add(id!);
        scheduled.add(Map.of(invocation.namedArguments));
        return Future<void>.value();
      case #cancel:
        pending.remove(id);
        return Future<void>.value();
      case #pendingNotificationRequests:
        if (failList) {
          return Future<List<PendingNotificationRequest>>.error(
            StateError('no queue'),
          );
        }
        return Future<List<PendingNotificationRequest>>.value([
          for (final id in pending)
            PendingNotificationRequest(id, null, null, null),
        ]);
      case #getNotificationAppLaunchDetails:
        return Future<NotificationAppLaunchDetails?>.value();
      case #resolvePlatformSpecificImplementation:
        return null;
    }
    return super.noSuchMethod(invocation);
  }

  Map<Symbol, dynamic> get last => scheduled.last;
}

String _dayKey(DateTime at) {
  final local = at.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePlugin plugin;
  late NexReminders reminders;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NexReminders.debugSupported = true;
    plugin = _FakePlugin();
    reminders = NexReminders(plugin: plugin);
  });
  tearDown(() => NexReminders.debugSupported = null);

  /// Half past ten at night in UTC: the moment of the day where an instant's
  /// UTC date and its date on the wall are not the same date east of
  /// Greenwich — and therefore the moment a check logged from a habit
  /// reminder lands on the wrong square.
  final at = DateTime.utc(2027, 3, 2, 22, 30);

  test('a module reminder carries the day it rings on, on the wall', () async {
    await reminders.scheduleModule(
      'habits',
      'habit:walk',
      at: at,
      title: 'Habits',
      body: 'Walk',
      sourceKind: 'habit',
      sourceId: 'walk',
      habitCounted: false,
    );
    final target = NexModuleTarget.parse(plugin.last[#payload] as String);
    expect(target!.day, _dayKey(at));
    // The instant is unchanged: only the day the buttons write against is
    // local.
    expect(
      (plugin.last[#scheduledDate] as DateTime).millisecondsSinceEpoch,
      at.millisecondsSinceEpoch,
    );
  });

  test('a module reminder honours the app lock, like a note does', () async {
    Future<NotificationVisibility?> visibilityFor(bool locked) async {
      reminders.hideOnLockScreen = () => locked;
      await reminders.scheduleModule(
        'medicine',
        'med:1',
        at: at,
        title: 'Medicine',
        body: 'One tablet',
      );
      final details = plugin.last[#notificationDetails] as NotificationDetails;
      return details.android!.visibility;
    }

    expect(await visibilityFor(true), NotificationVisibility.secret);
    expect(await visibilityFor(false), NotificationVisibility.private);
  });

  test('a module alarm the system did not keep is reported', () async {
    plugin.dropSchedules = true;
    final ok = await reminders.scheduleModule(
      'medicine',
      'med:2',
      at: at,
      title: 'Medicine',
      body: 'One tablet',
    );
    expect(ok, isFalse);
    expect(reminders.lastError, isNotNull);
  });

  test(
    'a reminder can still be turned off when the queue will not read',
    () async {
      plugin.failList = true;
      await expectLater(reminders.cancelModule('medicine'), completes);
    },
  );
}
