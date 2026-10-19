import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_core/nex_core.dart';

/// Stands in for the notification plugin: what is waiting to ring, what is
/// on the screen, and what was taken off it.
class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final pending = <int>{};
  final showing = <int>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final id = invocation.namedArguments[#id] as int?;
    switch (invocation.memberName) {
      case #initialize:
        return Future<bool?>.value(true);
      case #zonedSchedule:
        // Scheduling under an id replaces its alarm; it never touches a
        // notification on the screen.
        pending.add(id!);
        return Future<void>.value();
      case #cancel:
        // The plugin's cancel: the alarm and the notification, both.
        pending.remove(id);
        showing.remove(id);
        return Future<void>.value();
      case #pendingNotificationRequests:
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

  /// An alarm going off: it leaves the queue and shows.
  void ring(int id) {
    pending.remove(id);
    showing.add(id);
  }
}

/// 2.1.9: a reminder that has rung stays in the notification shade until it
/// is tapped or dismissed. Opening the app re-arms every alarm, and each
/// re-arm began with the plugin's cancel — which also takes the shown
/// notification away — so opening the app cleared them all.
void main() {
  late _FakePlugin plugin;
  late NexReminders reminders;

  setUp(() {
    NexReminders.debugSupported = true;
    plugin = _FakePlugin();
    reminders = NexReminders(plugin: plugin);
  });
  tearDown(() => NexReminders.debugSupported = null);

  Note daily(String id) {
    final now = DateTime.now().toUtc();
    return Note(
      id: id,
      type: NoteType.text,
      content: 'water the plants',
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now.subtract(const Duration(days: 3)),
      deviceId: 'd',
      rev: 1,
      syncState: SyncState.synced,
      dueAt: now.subtract(const Duration(days: 2)),
      dueRepeat: NoteRepeat.daily,
    );
  }

  test('a repeating reminder that rang survives the launch re-arm', () async {
    final note = daily('n1');
    await reminders.schedule(note);
    final id = NexReminders.idFor('n1');
    plugin.ring(id);
    expect(plugin.showing, {id});

    // What opening the app does.
    await reminders.syncFromLibrary([note]);
    expect(plugin.showing, {id}, reason: 'still in the shade');
    expect(plugin.pending, {id}, reason: 'and the next one is armed');
  });

  test('a recurring item that rang survives the launch re-arm', () async {
    final now = DateTime.now();
    final item = NexCommitment(
      id: 'c1',
      title: 'insurance',
      cadence: NexCadence.days,
      every: 1,
      dueAt: now.add(const Duration(hours: 5)),
      notify: true,
      createdAt: now,
      updatedAt: now,
    );
    final id = NexReminders.commitmentIdFor('c1');
    await reminders.scheduleCommitment(item);
    plugin.ring(id);
    await reminders.syncFromLibrary(const [], commitments: [item]);
    expect(plugin.showing, contains(id));
    expect(plugin.pending, contains(id));
  });

  test('an alarm no longer wanted is taken back; a shown one is not', () async {
    final now = DateTime.now();
    final item = NexCommitment(
      id: 'c2',
      title: 'rent',
      cadence: NexCadence.days,
      every: 1,
      dueAt: now.add(const Duration(hours: 5)),
      notify: true,
      createdAt: now,
      updatedAt: now,
    );
    final id = NexReminders.commitmentIdFor('c2');
    await reminders.scheduleCommitment(item);
    expect(plugin.pending, {id});
    // Paused before it rang: the alarm goes.
    await reminders.scheduleCommitment(item.copyWith(paused: true));
    expect(plugin.pending, isEmpty);

    // Paused after it rang: nothing is pending, and what shows stays.
    await reminders.scheduleCommitment(item);
    plugin.ring(id);
    await reminders.scheduleCommitment(item.copyWith(paused: true));
    expect(plugin.showing, {id});
  });

  test('clearing a reminder by hand still takes it off the screen', () async {
    final note = daily('n2');
    await reminders.schedule(note);
    final id = NexReminders.idFor('n2');
    plugin.ring(id);
    await reminders.cancel('n2');
    expect(plugin.showing, isEmpty);
  });
}
