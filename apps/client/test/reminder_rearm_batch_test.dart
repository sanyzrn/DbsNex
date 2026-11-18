import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_core/nex_core.dart';

/// Stands in for the notification plugin, counting how often the alarm
/// queue is read — the number the launch re-arm used to multiply by itself
/// (one whole-queue deserialization per re-armed reminder).
class _CountingPlugin implements FlutterLocalNotificationsPlugin {
  final pending = <int>{};
  final refuse = <int>{};
  var queueReads = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final id = invocation.namedArguments[#id] as int?;
    switch (invocation.memberName) {
      case #initialize:
        return Future<bool?>.value(true);
      case #zonedSchedule:
        // The system that says yes and keeps nothing: an id in `refuse` is
        // accepted (the call returns normally) and never held.
        if (!refuse.contains(id)) pending.add(id!);
        return Future<void>.value();
      case #cancel:
        pending.remove(id);
        return Future<void>.value();
      case #pendingNotificationRequests:
        queueReads++;
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
}

/// The launch re-arm (`syncFromLibrary`) schedules every upcoming reminder
/// and then checks the whole batch with one queue read. Before, each
/// `schedule` read the queue back for itself: R reminders meant R+1 reads
/// of a queue that itself holds R alarms — a hundred reminders was ten
/// thousand entry deserializations in the first seconds of a launch.
void main() {
  late _CountingPlugin plugin;
  late NexReminders reminders;
  late List<String> diagnostics;

  // The timezone the reminder code asks the platform for: without a handler
  // every schedule would end with the timezone warning folded into
  // `lastError`, which is not what these tests are about.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (
          call,
        ) async {
          if (call.method == 'getLocalTimezone') return 'Etc/UTC';
          return null;
        });
  });

  Note noteWithReminder({required String suffix}) {
    final now = DateTime.now().toUtc();
    return Note(
      id: 'note-$suffix',
      type: NoteType.text,
      content: 'reminder note $suffix',
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
      dueAt: now.add(const Duration(days: 3)),
    );
  }

  setUp(() {
    NexReminders.debugSupported = true;
    plugin = _CountingPlugin();
    diagnostics = [];
    reminders = NexReminders(plugin: plugin)..onDiagnostic = diagnostics.add;
  });
  tearDown(() => NexReminders.debugSupported = null);

  test('the re-arm reads the queue once for the whole batch', () async {
    final notes = [for (var i = 0; i < 12; i++) noteWithReminder(suffix: '$i')];

    await reminders.syncFromLibrary(notes);

    // One read for the prune, one for the batch verification — and not
    // thirteen, one per re-armed reminder.
    expect(plugin.queueReads, 2);
    expect(
      {for (final note in notes) NexReminders.idFor(note.id)},
      everyElement(isIn(plugin.pending)),
      reason: 'every re-armed alarm is back in the queue',
    );
  });

  test('an alarm the system dropped is re-armed by the sweep', () async {
    final notes = [for (var i = 0; i < 4; i++) noteWithReminder(suffix: '$i')];
    // The alarms were there once, and the system quietly dropped one.
    final dropped = NexReminders.idFor(notes.first.id);
    for (final note in notes) {
      await reminders.schedule(note, verify: false);
    }
    plugin.pending.remove(dropped);

    await reminders.syncFromLibrary(notes);

    expect(plugin.queueReads, 2);
    // The sweep re-armed the dropped alarm: it is wanted again.
    expect(plugin.pending, contains(dropped));
    expect(reminders.lastError, isNull);
  });

  test('a single scheduled note still verifies itself', () async {
    final note = noteWithReminder(suffix: 'solo');

    await reminders.schedule(note);

    expect(plugin.queueReads, 1);
    expect(reminders.lastError, isNull);
  });

  test('a note whose alarm the system will not keep is reported', () async {
    // The system accepts the schedule and keeps nothing: the re-arm's own
    // verification has to notice, the way the per-note `_verify` did.
    final notes = [noteWithReminder(suffix: 'lost')];
    plugin.refuse.add(NexReminders.idFor(notes.first.id));

    await reminders.syncFromLibrary(notes);

    expect(reminders.lastError, 'the system did not keep the alarm');
    expect(diagnostics.any((line) => line.contains('did not keep')), isTrue);
  });
}
